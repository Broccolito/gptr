# Track 19 — High-performance R tooling recommendations and harness-internals benchmarks

Requirement covered: **REQ-10** (minimal tool surface; recommend and opportunistically use
high-performance packages, fall back to base R), with direct consequences for REQ-01 (Rcpp bar),
REQ-02/03 (CRAN, cross-platform), REQ-05..09 (tool internals), REQ-21 (object inspection),
REQ-28 (skills), REQ-31 (system prompt), REQ-33 (parallel workers), D-11, D-20, D-21.

Date of research: 2026-09-29 (CRAN metadata queried 2026-09-30 01:33 UTC).
Machine: Apple M2 (Mac14,2), 8 cores, 24 GiB RAM, macOS 26.6.2, R 4.4.3 (aarch64-apple-darwin20),
PCRE 10.44 **without JIT**, ICU 78.1, TRE 0.8.0.
Scratch directory with every script and raw output:
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/`
(abbreviated below as `$W`).

**Measurement caveat (read first).** Other research agents were running on the same machine; the
load average was 14–72 on 8 cores during these runs (`uptime` at 18:36 → 14.57; at 19:08 → 71.81).
Absolute times are therefore inflated and noisy (one prior run of the same JSON script was ~2x
slower than my re-run). **Use the ratios between methods, not the absolute numbers.** Multi-threaded
code (data.table, arrow, duckdb, qs2) is penalised most by oversubscription. Package versions used
in benchmarks are sometimes older than current CRAN because CRAN no longer builds macOS binaries for
R 4.4 (e.g. qs2 0.1.7 benchmarked vs 0.3.1 current); see §2.2.

**Prior work.** A previous researcher on this track left scripts in `$W` (`00_installed.R`,
`b1_json.R`, `common.R`, `cran_status.R`, `cran_db.R`, `bin_avail.R`, `install_private.R`,
`out_b1_json.txt`, `web/qs2_readme.html`). I treated them as unverified: I re-ran `b1_json.R`
under a UTF-8 locale (the prior run was in the C locale, which garbled its edge-case section; the
prior output is kept as `$W/out_b1_json_PRIOR_unverified.txt`), superseded the CRAN queries with
`cran_status2.R`, and wrote everything else new. No partial report existed at the report path.

---

## 1. Executive summary

1. **Base R is good enough for every harness internal measured; no Rcpp routine is justified**
   (REQ-01 bar not met). The only big wins come from *how* base R/jsonlite is used, not from new
   dependencies.
2. **JSON: keep `jsonlite` as the only JSON Import.** Parsing is fast enough (5–11 µs per SSE chunk;
   37 ms for a 5 MB session document; ~90 ms for a 5 MB JSONL session). Serialising is the slow part
   (7.5 ms for a 100 KB request body, 1.35 s for a 5 MB document), and it is solved by **caching each
   message's JSON once and assembling the body with `json_verbatim = TRUE`**: byte-identical output,
   ~10–55x faster, the ratio growing with the number of small messages (600 messages / 1 MB body:
   171 ms → 10 ms; 60 messages 12x; 200 short messages 56x; verification re-run 9.5x / 15x / 79x+). Session files must be **append-only
   JSONL** (append through a kept-open connection: 12 µs; full rewrite: 97 ms).
3. `yyjsonr` is 3–90x faster than jsonlite but **changes R-side semantics** (homogeneous arrays
   become atomic vectors: `"required": ["path"]` parses to `"path"`; 64-bit ints become strings;
   `NULL` serialises as `[]`). `RcppSimdJson` turns `{}`/`[]` into `NULL`. Neither is a drop-in; do
   not use them in the harness.
4. **Streaming accumulation:** append deltas to a pre-sized/doubling character buffer held in a
   **closure and updated with `<<-`** (50,000 deltas: 56–68 ms, linear). `paste0(acc, delta)` is
   quadratic (5,000 deltas: 426 ms; 50,000: 159 s). **Surprise (verified):** `env$buf[i] <- x` or
   `st$buf[[i]] <- x` executed *inside a per-delta callback function* copies the whole buffer every
   call (5,000 deltas: 142 MB allocated; 50,000: 13.75 GB, 2.9 s), even with a local alias or the
   environment passed as an argument, and even after `compiler::cmpfun()`. Connections
   (`rawConnection`, `textConnection`, file) are 5–57x slower than the closure buffer. Re-rendering
   the full text after every delta costs 13 s per 5,000 deltas; throttle to every ~50 deltas (96 ms).
5. **Reading a 50 MB / 900k-line text file:** `readLines()` 0.8–0.9 s, `brio` 0.5 s, `vroom_lines`
   0.5 s when materialised (99 ms only because it is lazy/ALTREP), `fread` 0.7 s. Base is fine for
   the read tool. For a 2,000-line window at line 400,001, `vroom_lines(skip=, n_max=)` takes 35–50 ms
   vs 0.3–0.56 s for base (scan skip / chunked connection) — the only place an optional accelerator
   (Suggests) pays off.
6. **Regex: use base PCRE (`perl = TRUE`) or `fixed = TRUE`; never TRE (the default) in grep/search
   tools.** On 100k lines TRE is ~6–55x slower than PCRE depending on the pattern (literal 6x,
   anchored 10x, alternation 2.1 s vs 74 ms = 28x; a verification re-run gave 8–75x), and
   `regexpr()` TRE 2.0 s vs PCRE 37 ms. On whole vectors PCRE matches or beats stringi/ICU regex
   (1.0–4.5x) even though PCRE JIT is **disabled** in this CRAN macOS build; stringi was slightly
   faster only when called once per small file (121 vs 165 ms for 2,000 files), and concatenating all
   lines into one PCRE call beat both (57 ms). `gregexpr()` allocated 1.54 GB on 100k lines — avoid.
   A pure-R grep over 2,019 files / 26 MB took 0.88 s vs 1.34 s for the system `grep -rnE`.
7. **Files:** `list.files(recursive = TRUE)` on 10k files: 99 ms (relative names) vs 264 ms
   (`full.names = TRUE`); `fs::dir_ls` 62 ms. `file.info(extra_cols = FALSE)` on 10k files 42 ms;
   `fs::file_info` 128 ms. Base is enough; `fs` is not needed. `utils::glob2rx()` has no `**` or
   path-segment semantics, so the find tool needs its own glob→regex.
8. **Sorting:** `order(chr)` uses locale collation (1e6 strings: 9.45 s) whereas
   `order(chr, method = "radix")` is 40x faster (238 ms) but byte-ordered (`"B" < "a"`). Natural
   ordering (`file2 < file10`) needs `stringi::stri_sort(numeric = TRUE)` (46 ms for 10k names).
9. **base64 (2 MiB):** all encoders take 9–25 ms. **`jsonlite::base64_enc()` inserts a newline every
   72 characters** (not valid for API image payloads without `gsub("\n", "", x, fixed = TRUE)`).
   Decode: jsonlite 43 ms, openssl 248 ms. Embedding a 2.8 MB base64 string via `toJSON` costs
   68 ms; splicing the string into cached JSON costs 20 ms.
10. **Hashing:** `rlang::hash()` (xxh128) / `rlang::hash_file()` are fastest (5 MB file: 0.9 ms vs
    `tools::md5sum` 20 ms). rlang is already in the dependency tree of httr2, so it is free. R ≥ 4.5.0
    adds `tools::sha256sum()` and `tools::md5sum(bytes=)` (absent in 4.4.3).
11. **Capability detection must never load namespaces.** `find.package()` + `Meta/package.rds`
    detects 40 packages in ~20 ms; `installed.packages()` takes ~220 ms (615 installed). Loading them
    instead would cost 36 s in total (HDF5Array 9.1 s, SingleCellExperiment 6.5 s, Seurat 4.0 s) —
    and `rlang::is_installed()` *does* load (it calls `requireNamespace()`).
12. **Installed ≠ loadable, and a failed load can crash the session later.** BPCells is installed
    here but fails to load (Homebrew upgraded `libhdf5`). After that failed `loadNamespace()`,
    **loading any other compiled package (jsonlite, data.table, duckdb, …) segfaults R 4.4.3**. This
    matches R bug PR#19029, whose fix is listed in **R 4.6.1** NEWS ("Overly long dyn.load() error
    messages … should no longer corrupt its state") — LIKELY the same bug, but not re-tested on
    R 4.6.1 (not installed here). gptr must probe loadability of not-yet-loaded compiled packages
    **in a child process** before `library()` in a live session that holds valuable objects
    (at least on R < 4.6.1).
13. **Worker processes do not inherit runtime `.libPaths()` changes.** mirai daemons launched while the
    package lived in a `.libPaths()`-added library hung for 600 s ("initial sync with dispatcher")
    without an R error in the parent (the child only printed "there is no package called 'mirai'"
    to stderr). Setting `R_LIBS` before launch fixed it (re-verified). Applies to gptr's worker sub-agents
    (D-12) and to the load probe.
14. **Locale hazard:** `Rscript` started without `LANG` (cron, some IDE runners, this agent environment)
    runs in the C locale. There, `jsonlite::toJSON()` writes the bytes of *unknown-encoded* non-ASCII
    strings as literal `"<c3><a9>"` (verified on raw bytes); UTF-8-*marked* strings are fine. Text
    from `readLines()` without `encoding=`, `system2()` output and source literals are unknown-encoded.
    Fix: read with `encoding = "UTF-8"` and run an `as_utf8_deep()` guard before serialisation
    (prototype verified in both locales).
15. **Goal 1 (steering):** verified current CRAN status of ~100 packages. `qs` was **archived on
    2026-01-17**; its successor `qs2` (0.3.1) cannot read `.qs` files. `polars` is **not on CRAN**
    (archived 2023-07-18; R-multiverse only). BPCells is GitHub/R-universe only. Bioconductor 3.23
    (R 4.6) hosts DelayedArray/HDF5Array/SingleCellExperiment/BiocParallel. R 4.6.1 is current.
16. Measured headline ratios for the steering table: `fwrite` 31x faster than `write.csv`;
    `read_csv_arrow` 46x / `fread` 13x faster than `read.csv`; duckdb filter+aggregate on Parquet
    without loading 19.5 ms vs 38 ms for a full `read_parquet`; `qs2` (4 threads) 22x faster to write
    than default `saveRDS`; `collapse::fmean` 21x faster than `tapply`; `kit::topn` 24x faster than
    `order()[1:10]`; `matrixStats::colSds` 3.8x faster than `apply(, 2, sd)`.
17. **Two agent traps worth putting in the system prompt:** a `pkg::` prefix inside data.table `j`
    disables GForce (`stats::median` 36x slower; data.table's verbose log confirms "GForce is on, but
    not activated"), and inside `collapse::fsummarise()` it forces per-group evaluation
    (4.68 s vs 49 ms, 95x). LLMs habitually write `pkg::fun`.
18. Deliverables in §3: a **~300–390 token system-prompt section** (`<r_performance>`), a compact
    **`<r_env>` capability section** (~220 tokens, generated at runtime), and a **`high-performance-r`
    skill** (SKILL.md + 2 reference files). All 18 R code blocks in the skill run without an R error,
    but the original mirai recipe silently returned 8 `miraiError` values (mirai returns errors as
    values); the recipe is corrected below (`.args = list(k = 2)`) and re-verified.
19. **Imports recommendation:** `jsonlite`, `httr2`, `cli`, `processx` (D-20) plus `rlang` and `ps`,
    which are already in that dependency tree (16 packages total, zero added install weight). Suggests:
    `vroom` (deep read windows), `stringi` (natural sort), `lobstr`, `parallelly`. Do **not** list the
    data-work packages (data.table, arrow, duckdb, …) at all: gptr never calls them; the agent's code
    does, conditioned on `<r_env>`.

---

## 2. Findings

### 2.1 How Pi surfaces tool guidance (parity reference)

VERIFIED (Pi commit `1b347794`, `packages/coding-agent/src/core/system-prompt.ts`):

- The system prompt is an ordered record of named sections. `preamble` is untagged; every other
  section is wrapped as `<name>\n…\n</name>` (lines 175–179). Section names must match
  `/^[a-z][a-z0-9_-]*$/` and may not be `preamble` (lines 52, 136–140).
- Default section order: `preamble`, `tools`, `rules`, `docs`, then `addendum` (append prompt),
  `project_context`, `skills`, `cwd`, then custom `sections` (lines 142–173).
- Each tool contributes an optional one-line **`promptSnippet`** (listed as `- name: snippet` in
  `<tools>`; tools without a snippet are omitted from that list) and optional **`promptGuidelines`**
  bullets merged, de-duplicated and emitted in `<rules>` (lines 81–118, 148–152;
  `core/extensions/types.ts:567-570`). Snippets are normalised to one line (`agent-session.ts:1601-1608`).
  Examples: read → "Read file contents" + "Use read to examine files instead of cat or sed."
  (`tools/read.ts:20-23`); bash → "Execute bash commands (ls, grep, find, etc.)"
  (`tools/bash.ts:45-48`); edit has four guidelines (`tools/edit.ts:43-51`).
- Pi never injects OS, installed software or hardware into the prompt; only `cwd`
  (line 170). The bash tool guideline tells the model it may inspect `PI_*` environment variables.
- When sections change mid-session Pi sends a **patch** of changed sections
  (`diffSystemPromptSections`, lines 204–216) rendered as
  `Updated system prompt section "<name>":` (`packages/ai/src/utils/text.ts:28-40`), so a volatile
  section does not rewrite the cached prompt head.
- Skills are listed in `<skills>` as `<available_skills><skill><name/><description/><location/>`
  with the instruction "Use the read tool to load a skill's file when the task matches its
  description." (`core/skills.ts:355-383`). Names: `^[a-z0-9-]+$`, ≤ 64 chars, no leading/trailing or
  double hyphen; description required, ≤ 1024 chars (`core/skills.ts:11-14, 95-127`).

Implication for gptr: the high-performance guidance should be (a) a short, static
`<r_performance>` section (or the `r` tool's `promptGuidelines`), (b) a volatile `<r_env>` section
placed **last** and updated by section patch when packages change, and (c) a `high-performance-r`
skill for progressive disclosure.

### 2.2 Current repository status of candidate packages (Goal 1)

VERIFIED — executed `$W/cran_status2.R` (`tools::CRAN_package_db()`, 25,273 rows, 2026-09-30 01:33 UTC)
plus the web pages cited. "Installed here" = version on this machine (system library or the private
library `$W/../../rlib`); benchmarks used those versions.

| Package | CRAN now | Published | Compiled | Installed here | Notes |
|---|---|---|---|---|---|
| data.table | 1.18.6.1 | 2026-08-24 | yes | 1.18.2.1 | |
| vroom | 1.7.1 | 2026-03-31 | yes | 1.7.1 | 21 recursive deps |
| arrow | 25.0.1 | 2026-08-23 | yes | 23.0.1.1 | SystemRequirements C++20 |
| readr | 2.2.0 | 2026-02-19 | yes | 2.2.0 | |
| nanoparquet | 0.5.2 | 2026-09-16 | yes | 0.4.3 (priv) | "Completely dependency free"; flat tables only |
| duckdb | 1.5.6 | 2026-09-29 | yes | 1.5.0 (priv) | |
| duckplyr | 1.2.1 | 2026-03-10 | no | 1.2.1 (priv) | |
| collapse | 2.1.8 | 2026-08-30 | yes | 2.1.6 (priv) | |
| dplyr / dtplyr | 1.2.1 / 1.3.3 | 2026-04-03 / 2026-02-11 | yes / no | same | |
| tidytable | 0.11.2 | 2024-12-11 | no | 0.11.2 (priv) | |
| polars / tidypolars | **not on CRAN** | polars archived 2023-07-18 "for policy violations"; tidypolars never on CRAN (no CRAN page or archive) | — | — | R-multiverse / R-universe only (polars 1.16.0 on R-multiverse) |
| matrixStats | 1.5.0 | 2025-01-07 | yes | 1.5.0 | |
| stringi / stringr | 1.8.9 / 1.6.0 | 2026-08-04 / 2025-11-04 | yes / no | 1.8.7 / 1.6.0 | |
| stringfish | 0.19.2 | 2026-08-04 | yes | 0.18.0 | dependency of qs2 |
| qs2 | 0.3.1 | 2026-08-21 | yes | 0.1.7 (priv) | Imports Rcpp, RcppParallel, stringfish |
| qs | **archived 2026-01-17** | "issues were not corrected despite reminders" | — | 0.27.3 | |
| fst | 0.9.8 | **2022-02-08** | yes | 0.9.8 (priv) | stale but on CRAN; "little-endian platform" |
| kit | 0.0.21 | 2026-01-23 | yes | 0.0.21 (priv) | |
| Matrix | 1.7-6 | 2026-07-25 | yes | 1.7-5 | recommended pkg |
| bigmemory | 4.6.6 | 2026-06-08 | yes | 4.6.4 (priv) | |
| BPCells | **not on CRAN or Bioconductor** | GitHub/R-universe 0.3.1 | yes | 0.3.1 (**not loadable**) | needs HDF5 system lib |
| DelayedArray / HDF5Array / SingleCellExperiment / BiocParallel / sparseMatrixStats | Bioconductor 3.23: 0.38.2 / 1.40.0 / 1.34.0 / 1.46.0 / 1.24.0 | — | — | 0.32.0 / 1.34.0 / 1.28.1 / 1.40.2 / 1.18.0 (older Bioc for R 4.4) | Bioc 3.23 "works with R version 4.6.0" |
| mirai / nanonext | 2.7.3 / 1.10.3 | 2026-09-24 / 2026-09-23 | no / yes | 2.6.1 / 1.8.1 (priv) | |
| future / future.apply / furrr | 1.76.0 / 1.20.2 / 0.4.0 | 2026-09-24 / 2026-02-20 / 2026-03-31 | no | 1.70.0 / 1.20.2 / 0.4.0 | |
| future.mirai | 1.0.0 | 2026-06-22 | no | 0.10.1 (priv) | |
| crew / targets | 1.3.3 / 1.12.0 | 2026-09-04 / 2026-02-09 | no | 1.3.0 / 1.12.0 (priv) | |
| parallelly | 1.48.0 | 2026-06-29 | yes | 1.46.1 | |
| bench / microbenchmark / profvis | 1.1.4 / 1.5.0 / 0.4.0 | 2025-01-16 / 2024-09-04 / 2024-09-20 | yes | 1.1.4 (priv) / 1.5.0 / 0.4.0 | |
| ggplot2 | 4.0.3 | 2026-04-22 | no | 4.0.2 | |
| scattermore / ggrastr | 1.2 / 1.0.2 | 2023-06-12 / 2023-06-01 | yes / no | same | Seurat rasterises through scattermore |
| rasterly | **archived 2022-10-03** ("check issues were not corrected despite reminders") | — | — | — | no maintained datashader port on CRAN |
| Seurat / SeuratObject | 5.5.1 / 5.4.0 | 2026-06-26 / 2026-04-11 | yes | 5.4.0 / 5.4.0 | |
| jsonlite | 2.0.0 | 2025-03-27 | yes | 2.0.0 | 0 non-base deps |
| yyjsonr / RcppSimdJson | 0.1.22 / 0.1.15 | 2026-04-05 / 2026-01-14 | yes | 0.1.21 / 0.1.15 (priv) | |
| digest / rlang / openssl / base64enc | 0.6.39 / 1.3.0 / 2.4.2 / 0.1-6 | | yes | 0.6.39 / 1.1.7 / 2.3.5 / 0.1-6 | |
| b64 / secretbase / xxhashlite | 0.1.7 / 1.3.1 / 0.2.2 | | yes | 0.1.7 / 1.2.0 / 0.2.2 (priv) | b64 needs Rust (Cargo) to build |
| httr2 / curl / processx / cli / fs / brio / lobstr | 1.3.0 / 8.0.0 / 3.9.0 / 3.6.6 / 2.1.0 / 1.1.5 / 1.2.2 | | | 1.2.2 / 7.0.0 / 3.8.6 / 3.6.6 / 2.1.0 / 1.1.5 / 1.2.0 | |
| disk.frame / mirai.promises | archived | 2026-01-30 ("requires archived package 'pryr'") / 2024-05-09 (maintainer's request) | | | |

Other verified facts:
- R 4.6.1 is the current release (2026-06-24) — https://cran.r-project.org/banner.shtml.
- `qs2` README: "qs2 is the successor to the qs package … It is not compatible with the original qs
  format." `qs_save(object, file, compress_level, shuffle, nthreads)`, `qs_read(file,
  validate_checksum, nthreads)`, `qd_save/qd_read` (qdata), `qs_to_rds()`, `rds_to_qs()` (same
  signatures in the 0.3.1 manual; 0.3.1 `qd_save()` adds `warn_unsupported_types`). The 0.3.1
  manual also states that `nthreads` > 1 "emit[s] a warning and fall[s] back to 1" when TBB is not
  available, and `rds_to_qs()` accepts only gzip-compressed RDS input.
- nanoparquet limitations: "Nested Parquet types are not supported", no encryption, no URLs,
  "always reads the data … into memory".
- duckdb: larger-than-memory workloads spill to disk; `temp_directory` defaults to
  `<database_name>.tmp` or `.tmp` in in-memory mode (i.e. **in the working directory**);
  `memory_limit` default "80% of RAM"; `threads` default "# CPU cores";
  `max_temp_directory_size` default "90% of available disk space".
- duckplyr: `library(duckplyr)` overwrites dplyr methods session-wide (`methods_restore()` reverts);
  frames from `read_parquet_duckdb()` are "prudent" (default prudence "thrifty"): executed here,
  `nrow()` on a 1e6-row × 8-column frame errored "Materialization would result in more than 125000
  rows. Use `collect()` or `as_tibble()`". **The limit is 1,000,000 cells (rows × columns), not
  125,000 rows** (verification: 1/2/8 columns → limits of 1,000,000 / 500,000 / 125,000 rows;
  duckplyr prudence article: "fewer than 1,000,000 cells (rows multiplied by columns)").
  Telemetry: *uploads* are opt-in only, but local *collection* of fallback logs is on by default
  (written under `tools::R_user_dir("duckplyr", "cache")`; disable with `DUCKPLYR_FALLBACK_COLLECT=0`).
- purrr ≥ 1.1.0 `in_parallel()` runs `map()` on mirai daemons; functions must declare their data via
  named `...` arguments. It needs the Suggests `carrier (>= 0.3.0)` and `mirai (>= 2.5.1)`
  (purrr 1.2.2 DESCRIPTION; a verification call without carrier errored).
- `future` option `future.globals.maxSize` default `500 * 1024^2` (500 MiB) (installed help).
- Seurat `DimPlot(raster = NULL)` "automatically rasterizes if plotting more than 100,000 cells" and
  `raster.dpi` is "passed to geom_scattermore()" (installed help). `SketchData()` defaults:
  `ncells = 5000`, `method = c("LeverageScore", "Uniform")`, `sketched.assay = "sketch"`.
- `SeuratObject::SplitLayers` is **not** exported; layers are split with
  `obj[["RNA"]] <- split(obj[["RNA"]], f = obj$sample)` (executed: `Layers()` → `"counts.a" "counts.b"`,
  after `JoinLayers()` → `"counts"`; assay class `Assay5`).

### 2.3 Goal 1 measurements (evidence for the steering table)

All VERIFIED by execution unless noted; medians from `bench::mark`; loaded machine.

**Delimited I/O, 1e6 rows × 8 columns (77 MB CSV)** — `$W/b9_io.R`

| Operation | Median | Relative |
|---|---|---|
| write: `write.csv` | 4.84 s | 30.8x |
| write: `data.table::fwrite` | 157 ms | 1 |
| write: `arrow::write_csv_arrow` | 653 ms | 4.2x |
| write: `readr::write_csv` / `vroom_write` | 1.38 s / 1.59 s | 8.8x / 10.1x |
| read: `read.csv` | 5.16 s | 45.6x |
| read: `arrow::read_csv_arrow` | 113 ms | 1 |
| read: `vroom` (ALTREP, then forced) | 346 ms | 3.1x |
| read: `data.table::fread` | 390 ms | 3.4x |
| read: `readr::read_csv(lazy = FALSE)` | 470 ms | 4.2x |
| read: duckdb `read_csv_auto` | 539 ms | 4.8x |

**Parquet** (same data, 23–24 MB files): write duckdb COPY 219 ms, arrow 367 ms, nanoparquet 389 ms;
read arrow 38 ms, nanoparquet 63 ms, duckdb 135 ms; **filter + group aggregate without loading**:
duckdb SQL 19.5 ms, `arrow::open_dataset` + dplyr 50 ms.

**Serialisation of the 49.6 MB data.frame**

| Method | Write | File | Read |
|---|---|---|---|
| `saveRDS` (gzip default) | 4.61 s | 19.9 MB | 590 ms |
| `saveRDS(compress = FALSE)` | 362 ms | 59.6 MB | 436 ms |
| `saveRDS(compress = "xz")` | 28.3 s | 16.9 MB | — |
| `qs2::qs_save` (1 thread) | 473 ms | 19.1 MB | 210 ms |
| `qs2::qs_save(nthreads = 4)` | 212 ms | 19.1 MB | 194 ms |
| `qs2::qd_save` | 309 ms | 18.3 MB | 169 ms |
| `qs::qsave` (archived) | 327 ms | 16.9 MB | 181 ms |
| `fst::write_fst` | 633 ms (min 190) | 34.5 MB | 126 ms |

All round-trips `identical()`. `qd_save()` on a list containing an `lm` fit warned "Objects of type
language are not supported in qdata format"; `qs_save()` handled it. **Correction (verified):**
`qd_save()` does not refuse such objects — it still writes the file and silently drops the language
parts (read back, the `lm` has `$call` and `$terms` = `NULL`), so a model saved this way is broken. `qs_to_rds()` output read back
identically with `readRDS()`.

**Grouped statistics, sorting, top-n, matrices** — `$W/b10_wrangle.R`, `b10b`, `b10c`

| Task | Result |
|---|---|
| mean by 1e4 groups, 5e6 rows | `collapse::fmean(x, g)` 21 ms; data.table 67 ms; tidytable 73 ms; dtplyr 87 ms; dplyr 139 ms; base `rowsum()/tabulate` 221 ms; `tapply` 433 ms; `aggregate` 2.14 s |
| 3 stats by 2 keys (~254k groups), 1e6 rows | data.table 101 ms; collapse (qualified names) 3.04 s; dplyr 4.21 s; `aggregate` 8.3 s |
| collapse qualified vs unqualified (b10b) | `collapse::fsummarise(..., collapse::fsum(x))` 4.68 s vs `fsummarise(..., fsum(x))` 49 ms (95x); vector API with `GRP()` 46 ms |
| data.table GForce (b10c) | `median(x)` 245 ms vs `stats::median(x)` 8.78 s (36x); verbose: "GForce is on, but not activated for this query" for `base::mean`; "GForce optimized j to 'list(gmean(x))'" for `mean` |
| order 1e7 doubles | default (already radix) 313 ms; `collapse::radixorder` 337 ms; `sort` 616 ms; `setorder` 563 ms |
| order 1e6 strings | default (locale) 9.45 s; `method = "radix"` 238 ms; collapse 492 ms; data.table `forderv` 1.91 s; `stringi::stri_order` 2.61 s; with `numeric = TRUE` 13 s |
| top-10 of 1e7 | `kit::topn` 17.5 ms; `sort(partial=)` 160 ms; `order()[1:10]` 419 ms; `frank` 1.47 s |
| col stats 2000×5000 | `colMeans` 15.8 ms; `collapse::fsd` 40 ms; `matrixStats::colSds` 67 ms vs `apply(sd)` 255 ms; `colMedians` 219 ms vs `apply(median)` 616 ms |
| sparse 20000×10000 @5% | 114.5 MB vs 1600 MB dense; `Matrix::rowSums` 21 ms |

R's own documentation (installed `?sort`): radix "is the default for … numeric vectors, integer
vectors, logical vectors and factors; otherwise shell"; for character vectors radix "collation does
not respect the locale", "Collation follows that with LC_COLLATE=C".

**Parallel back-ends** — `$W/b12_parallel.R` (median of 3)

| Measure | PSOCK | mirai 2.6.1 | future multisession | callr::r | mclapply (fork) |
|---|---|---|---|---|---|
| start 4 workers + 1 task + stop | 0.34 s | 0.87 s | 0.83 s | 0.28 s (1 proc) | 0.018 s |
| 200 tiny tasks, warm | 1 ms (`parLapply`), 29 ms (`clusterApply`) | 30 ms (`mirai_map`), 58 ms (200 × `mirai()`) | — | — | — |
| send 76 MB data.frame to 4 workers | 1.42 s (`clusterExport`) | 2.35 s (`everywhere`), 2.20 s (map arg) | — | — | — |

First attempt (`$W/out_b12_parallel_FAILED_libpaths.txt`): mirai daemons could not find the mirai
package because it was only on a `.libPaths()` added at run time; the parent printed
"mirai: initial sync with dispatcher [600 secs elapsed]" with no error. `Sys.setenv(R_LIBS = …)`
before `daemons()` fixed it (VERIFIED).

`?future::multicore`: "forking is not supported on Microsoft Windows … process forking may break some
R environments such as RStudio"; `?parallel::mclapply`: "It is strongly discouraged to use these
functions in GUI or embedded environments" (installed help).

### 2.4 Goal 2 — harness internals

#### 2.4.1 JSON (`$W/b1_json.R`, `$W/b1b_json_extra.R`; jsonlite 2.0.0, yyjsonr 0.1.21, RcppSimdJson 0.1.15)

| Payload | jsonlite | yyjsonr | RcppSimdJson |
|---|---|---|---|
| parse SSE delta (132 B) | `parse_json` 5.1 µs; `fromJSON(simplifyVector = FALSE)` 8.7 µs; `fromJSON()` default 29.4 µs | 1.4–1.6 µs | 12.8 µs |
| parse OpenAI chunk (238 B) | 11.4 µs | 2.0 µs | 13.1 µs |
| parse 1000 chunks | lapply 8.3 ms; concatenated as one array 2.5 ms | 0.96 ms (array) | 0.99 ms |
| parse request body (102 KB) | 451 µs | 171 µs | 245 µs |
| serialise request body | **7.5 ms** | 183 µs | — |
| serialise one session entry (~700 B) | 94 µs | 2.8 µs | — |
| parse 5 MB session as one JSON array | 37 ms | 12.5 ms | 18 ms |
| parse 5 MB session JSONL (3400 lines) | 91–93 ms (lapply or paste to array); `stream_in` 484 ms | `read_ndjson_file` 17.7 ms | 48 ms |
| serialise 5 MB session | **1.35 s** | 14.8 ms | — |

Semantics (VERIFIED, same script): `identical(jsonlite, yyjsonr)` FALSE on the request body;
`tools[[1]]$input_schema$required` is `list("path")` (jsonlite, simdjson) but `"path"` (yyjsonr);
`9007199254740993` → `num 9.01e+15` (jsonlite, precision lost) vs `chr "9007199254740993"` (yyjsonr);
`{}` and `[]` → `NULL` (simdjson); serialising `NULL` → `null` (jsonlite with `null = "null"`) vs
`[]` (yyjsonr).

Request assembly (`b1b`): serialise each message once (`toJSON(msg, auto_unbox = TRUE, null = "null",
digits = NA)`), keep the string with class `"json"`, and build the body with `json_verbatim = TRUE`
(or string concatenation). Output was `identical()` to a full `toJSON()` of the request. Per turn:
60 messages / 114 KB: 18.8 ms → 1.6 ms; 600 messages / 1.03 MB: 171 ms → 10–11 ms; 200 messages
(`proto_harness_helpers.R`): 15.5 ms → 0.28 ms.

JSONL append of one ~1 KB entry to a 5 MB file: kept-open connection + `flush()` 12 µs;
`cat(append = TRUE)` 68 µs; open/`writeLines`/close 57 µs; rewrite whole file 97 ms.

httr2 1.2.2 `req_body_json()` serialises with `jsonlite::toJSON(auto_unbox = TRUE, digits = 22,
null = "null")` (printed function source; same defaults in the httr2 1.3.0 reference page), so a
pre-serialised body should be sent with `req_body_raw(body, type = "application/json")`
(`req_body_raw(req, body, type = "")` — pass the type explicitly).

#### 2.4.2 Streaming string accumulation (`$W/b2_strings.R`, `b2b`–`b2f`)

| Strategy | 500 deltas | 5,000 | 50,000 |
|---|---|---|---|
| doubling pre-allocated `character` (local) | 211 µs | 2.4 ms | 25 ms |
| `list` + `[[n]] <-` (local) | 334 µs | 3.1 ms | 38 ms |
| `e$buf[[length(e$buf)+1]] <- x` inline loop | 394 µs | 3.4 ms | 42 ms |
| **env buffer updated inside a `push()` callback** | 846 µs | 39 ms / **142 MB** | **2.94 s / 13.75 GB** |
| `c(buf, x)` | 940 µs | 75 ms | 18.5 s |
| `rawConnection` + `writeBin` | 2.35 ms | 13.6 ms | 372 ms |
| `textConnection` + `cat` | 1.76 ms | 12.8 ms | 1.42 s |
| file connection | 2.22 ms | 14.7 ms | 256 ms |
| `paste0(acc, x)` | 4.9 ms | 426 ms | 159 s elapsed (`system.time`) |

All strategies returned identical text (including `\n`, `é`, `中`). Pinpointing (`b2c`, `b2d`,
5,000 appends): inline loop with `e$buf[n] <- x` in the frame that created `e`: 2.5 ms / 294 KB;
the same statement inside a called `push()` function: 48–63 ms / 142–191 MB, whether `e` is a free
variable, a local alias (`st <- e`), or an argument, and for lists too; `compiler::cmpfun(push)` did
not help (`b2f`, 191 MB). **Fixes that are linear:** closure variables updated with `<<-`
(5,000: 7.2 ms; 50,000: 68 ms, 2.7 MB) and a list-of-256-slot-chunks (7.1 ms; 91 ms). The mechanism
(why the called-function path duplicates) is UNCERTAIN; the rule is VERIFIED.

UI implication: re-pasting the full text after every delta (5,000 deltas) took 13 s; `paste0`
accumulation 2.2 s; rebuilding every 50 deltas 96 ms. Echoing each delta with `cat()` to a sink costs
~4 µs per delta (20.6 ms / 5,000).

#### 2.4.3 Reading a 50 MB text file (`$W/b3_readfile.R`, `b3b`; 53.5 MB, 900,000 lines, mixed UTF-8)

| Operation | Median |
|---|---|
| `readLines(f)` | 0.80–0.94 s |
| `readLines(f, encoding = "UTF-8")` | 1.29 s (noisy) |
| `readLines(file(f, encoding = "UTF-8"))` (re-encoding) | 1.46 s |
| `brio::read_lines` | 0.50–0.55 s |
| `vroom::vroom_lines` lazy / forced / `altrep = FALSE` | 99 ms / 519 ms / 1.19 s |
| `data.table::fread(sep = "")` forced | 0.67–0.79 s |
| `readr::read_lines`, `scan(sep = "\n")`, `stringi::stri_read_lines` | 1.44 s, 1.61 s, 1.66 s |
| whole file as one string: `brio::read_file` / `readr::read_file` / `readChar(useBytes = TRUE)` / `rawToChar(readBin())` | 128 / 141 / 153 / 169 ms |
| first 2,000 lines: `readLines(n = 2000)` / `vroom_lines(n_max = 2000)` | 1.8 ms / 1.5 ms |
| lines 400,001–402,000: `vroom_lines(skip, n_max, altrep = FALSE)` | 35–50 ms |
| same: `scan(skip, nlines)` / chunked `readLines(con, n = 50000)` skip / `readBin` newline scan + `seek` | 297–345 ms / 546–563 ms / 489 ms |
| same: `readLines(f)[idx]` | 1.18 s |
| count lines: `vroom_lines` length / chunked `readBin` `sum(r == 10)` / `length(readLines())` | 91 ms / 346 ms / 1.21 s |

`readLines()` returns `Encoding() == "unknown"`; with `encoding = "UTF-8"` non-ASCII lines are marked
`"UTF-8"` (ASCII lines stay `"unknown"`, which is harmless).

#### 2.4.4 Regex engines on 100k lines (`$W/b4_regex.R`; 66.6 bytes/line)

ASCII set (UTF-8 set with 78% non-ASCII lines behaves the same except TRE allocates 27 MB for
wide-char conversion):

| Pattern | TRE (default) | PCRE `perl = TRUE` | PCRE + `useBytes` | `fixed = TRUE` | stringi |
|---|---|---|---|---|---|
| literal `data.table` | 141 ms (escaped regex) | 24 ms | — | 18.5 ms | `stri_detect_fixed` 13 ms; regex 51 ms |
| `^\s*library\(` | 92 ms | 9.6 ms | 8.9 ms | — | 43 ms (stringr 46 ms) |
| `\b(read|write)_[a-z]+\(` | 2.10 s | 74 ms | 51 ms | — | 74 ms |
| case-insensitive `error` | 103 ms | 35.5 ms | — | `tolower` + fixed 227 ms | `stri_detect_fixed(case_insensitive)` 38 ms; regex 68 ms |
| match positions | `regexpr` 2.02 s | `regexpr` 36.5 ms; `gregexpr` 830 ms / **1.54 GB** | — | — | `stri_locate_first_regex` 94 ms |
| 2,000 files × 50 lines, one call per file | 1.98 s | 165 ms | — | — | 121 ms |
| same, concatenated then split | — | 57 ms | — | — | — |

All engines returned identical match vectors (checked). `pcre_config()` reports `JIT FALSE` on this
CRAN macOS arm64 build; on other platforms JIT availability is UNCERTAIN, so the harness should not
depend on it (PCRE already wins without it). Real corpus (`b17_grep_tool.R`, Pi `packages/`,
2,019 files, 26.4 MB): per-file `readLines(encoding = "UTF-8", skipNul = TRUE)` + `grepl(perl = TRUE)`
0.88 s (TRE 1.73 s); reading alone 0.68 s; NUL sniffing of the first 8,000 bytes 0.20 s; system
`grep -rnE` 1.34 s; same 76 matches.

#### 2.4.5 File discovery and metadata on 10k files (`$W/b5_files.R`)

| Operation | Median |
|---|---|
| `list.files(recursive = TRUE)` relative / `full.names = TRUE` | 99 ms / 264 ms |
| `list.files(pattern = "\\.R$", recursive = TRUE)` | 83 ms |
| `fs::dir_ls(recurse = TRUE)` / with glob | 62 ms / 76 ms |
| `Sys.glob` 2 levels, `list.dirs` | 77 ms, 77 ms |
| `file.info()` / `file.info(extra_cols = FALSE)` | 43 ms / 42 ms |
| `file.mtime()` / `file.size()` / `file.exists()` | 62 / 91 / 57 ms |
| `fs::file_info()` / `fs::dir_info(recurse = TRUE)` | 128 ms / 291 ms |
| sort by mtime / size | < 1 ms |
| `sort(names)` locale vs radix vs `stri_sort(numeric = TRUE)` | 64 ms vs 1.6 ms vs 46 ms |

`list.files()` skips dot-directories unless `all.files = TRUE` (10,000 vs 10,500 with `.git`).
`utils::glob2rx("**/*.qmd")` → `^.*.*/.*\.qmd$` and `glob2rx("*.R")` → `^.*\.R$` (the `*` crosses
`/`). Ordering demo: locale `_z.R a.R B.R é.R file1.R file10.R File2.R`; radix
`B.R File2.R _z.R a.R file1.R file10.R é.R`; stringi natural `_z.R a.R B.R é.R file1.R File2.R file10.R`.

#### 2.4.6 base64 of a 2 MiB image (`$W/b6_base64.R`)

| | base64enc | jsonlite | openssl | b64 | secretbase |
|---|---|---|---|---|---|
| encode | 9.7 ms | 9.8 ms (**adds `\n` every 72 chars**) | 12.2 ms | 8.9 ms | 24.6 ms |
| decode | 29.6 ms | 42.6 ms | 248 ms | 3.7 ms | 167 ms |

Output identical to base64enc for openssl, b64, secretbase; jsonlite differs only by newlines
(first newline at character 73; executed). A request body containing the 2.8 MB base64 string:
`jsonlite::toJSON` 68 ms; `json_verbatim` with a pre-quoted string 114 ms (no gain: jsonlite still
scans); splice into cached JSON with `sub(fixed = TRUE)` 20 ms; yyjsonr 10 ms. `paste0` data URI
7.8 ms vs `base64enc::dataURI` 19 ms.

#### 2.4.7 Hashing (`$W/b7_hash.R`)

| Input | Fastest | Others |
|---|---|---|
| 1 KB string | `secretbase::siphash13` 2.1 µs, `rlang::hash` 2.8 µs, xxhashlite 3.0 µs | digest xxhash64 8 µs, md5 13 µs; openssl md5 31 µs |
| 1 MB string | `rlang::hash` 71 µs | xxhashlite 123 µs; digest xxhash64 154 µs; openssl sha256 709 µs; openssl md5 2.4 ms; digest md5 3.7 ms |
| 5.5 MB file | `rlang::hash_file` 0.88 ms | digest xxhash64 file 2.45 ms; openssl sha256(con) 8.9 ms; **`tools::md5sum` 19.7 ms**; digest md5 23 ms; secretbase sha256 35 ms |
| data.frame 1e5 × 3 | `rlang::hash` 6.3 ms | xxhashlite 6.8 ms; digest xxhash64 9.9 ms; md5 15.8 ms |
| 1000 short strings | `digest::getVDigest("md5")` 1.36 ms | `openssl::md5(vector)` 1.96 ms; `vapply(rlang::hash)` 2.27 ms; `vapply(digest)` 11.5 ms |

MD5 agrees across `tools::md5sum`, digest and openssl. `rlang::hash("a")` hashes the serialised
object (`4d52a7da…`), `rlang::hash_file` of a file containing `a` gives `a96faf70…` — string and file
hashes are not interchangeable. `rlang::hash()` of a UTF-8 vs latin1 `é` differ. R 4.4.3 has no
`tools::sha256sum`; R 4.5.0 NEWS: "Added function sha256sum() in package tools analogous to md5sum()"
and "md5sum() can be used to compute an MD5 hash of a raw vector of bytes by using the bytes=
argument".

#### 2.4.8 Object inspection (REQ-21; `$W/b15_objsize.R`)

`object.size(1:1e9)` 3.7 Gb vs `lobstr::obj_size` 680 B (ALTREP); list with three references to one
400 MB vector: 1.1 Gb vs 400 MB; 5e5 small lists: 251.8 Mb vs 124 MB. Cost: `object.size` 155 ms vs
lobstr 610 ms (5e5 lists); 9.7 ms vs 76 ms (1e6-row data.frame). `str(max.level = 1, list.len = 5)`
of the 5e5-element list 245 ms; `summary(df)` 51 ms.

### 2.5 Capability detection (`$W/b8_capdetect.R`, `$W/proto_caps.R`)

- 40 packages, user library of 615 packages: `find.package()` + `readRDS(Meta/package.rds)` 19.8 ms;
  `system.file()` + `packageDescription()` 21.9 ms; `packageVersion()` in `tryCatch` 16.5 ms (but
  normalises `1.7-5` to `1.7.5`); `installed.packages(noCache = TRUE)` 219 ms. A and B agree exactly.
- `find.package()` returns already-loaded namespaces first (bench was found although its library had
  been removed from `.libPaths()`): desirable.
- Fresh-process `requireNamespace()` times: HDF5Array 9.15 s, SingleCellExperiment 6.52, DelayedArray
  5.36, Seurat 3.97 (112 namespaces), SeuratObject 2.12, arrow 1.30, ggplot2 1.25, BPCells 1.02
  (FALSE), Matrix 0.97, ggrastr 0.88, scattermore 0.80, dtplyr 0.54, vroom 0.44, furrr 0.41, dplyr
  0.34, readr 0.33, profvis 0.27, stringr 0.18, stringfish 0.14, future 0.11, BiocParallel 0.11,
  future.apply 0.08, data.table 0.07, stringi 0.02, RcppParallel 0.01, matrixStats 0.01; total 36.4 s.
- `rlang::is_installed()` calls `requireNamespace()` (printed `rlang:::detect_installed` source), so it
  must not be used for detection.
- BPCells: `loadNamespace()` error "Library not loaded: /opt/homebrew/opt/hdf5/lib/libhdf5.310.dylib"
  (Homebrew now has hdf5 2.2.0). In a fresh process, `try(loadNamespace("BPCells"))` followed by
  `loadNamespace()` of duckdb, qs2, collapse, data.table, secretbase or jsonlite **segfaulted every
  time** ("address 0x202c29656c696620" = ASCII text " file), " from the dlerror message → a buffer
  overflow). Without the failed BPCells load, all loaded fine. R 4.6.1 NEWS: "Overly long dyn.load()
  error messages (C level dlerror()), should no longer corrupt its state, thanks to Ivan Krylov's
  PR#19029 report and patch."
- Prototype (`proto_caps.R`): detection of 36 registry packages 0.149 s; optional out-of-process load
  probe of the 23 compiled, unloaded, installed packages 29 s (2 at a time, loaded machine), correctly
  flagging only BPCells. Generated `<r_env>` block: 866 characters ≈ 217 tokens (chars/4).
- `parallelly::availableCores()` returns 2 when `_R_CHECK_LIMIT_CORES_=TRUE` (executed), which
  `R CMD check --as-cran` sets (R Internals "Tools"; https://rstudio.github.io/r-manuals/r-ints/Tools.html);
  `availableCores(omit = 1)` → 7 here. `ps::ps_system_memory()` (ps is a processx dependency)
  returns total/avail RAM cross-platform.

### 2.6 Encoding and locale (`$W/b14d_locale_bytes.R`, `b14e`, `proto_harness_helpers.R`)

Raw bytes of `jsonlite::toJSON()` output for the string `café`:

| Source of the string | C locale | UTF-8 locale |
|---|---|---|
| UTF-8-marked (`Encoding<-`, `readLines(encoding = "UTF-8")`, `parse_json`) | `c3 a9` correct | correct |
| `readLines()` default (unknown) | **`3c 63 33 3e 3c 61 39 3e` = `<c3><a9>`** | correct |
| `system2(stdout = TRUE)` | **`<c3><a9>`** | correct |
| string literal in a sourced file (unknown) | **`<c3><a9>`**; `enc2utf8()` also yields `<c3><a9>` | correct |
| `capture.output(print(x))` of a UTF-8 string | text itself contains `<U+00E9>` (R's printing) | correct |

`cat()` of a correct UTF-8 string in a C locale *displays* `<U+00E9>`; this is display only (my first
test, `b14_locale.R`, misread it; `b14d` checks bytes). `Rscript` without `LANG` gets `LC_CTYPE = "C"`
here. `Sys.setlocale("LC_CTYPE", "C.UTF-8" | "en_US.UTF-8" | "UTF-8")` all succeeded on macOS and a
capture under a scoped `C.UTF-8` produced UTF-8 bytes. R on Windows uses UTF-8 as native encoding
since R 4.2.0 via UCRT (Windows 10 November 2019 or newer) — R blog, 2022-11-07.

---

## 3. Exact specifications

### 3.1 System-prompt section (static, ship verbatim)

1,569 characters, 219 words ≈ 300–390 tokens (words×1.35 / chars÷4; no tokenizer available offline).
File: `$W/prompt_section.txt`.

```text
<r_performance>
You work in the user's live R session; objects in memory are the asset. Reuse them; never reload data or re-run slow steps unless asked.
- Use only packages installed per <r_env>. Ask before installing or updating any package; else take the base-R route.
- Check size first (dim(), object.size()); print head()/str(x, max.level = 1), never whole big objects. Avoid copies: data.table := / set*, rm() temporaries.
- CSV: data.table::fread/fwrite, arrow::read_csv_arrow or vroom, not read.csv. Parquet: arrow or nanoparquet. Larger than RAM: duckdb SQL on files or arrow::open_dataset; filter/aggregate before collect(). Objects: qs2::qs_save, else saveRDS(compress = FALSE).
- Grouping >1e6 rows: data.table or collapse, not aggregate(). Inside data.table j and collapse::fsummarise call mean(x)/fmean(x) unqualified; pkg::fun there disables the fast path (up to 100x slower).
- Regex: grepl(perl = TRUE) or fixed = TRUE, never the default engine on large vectors.
- Sort: order(method = "radix") (byte order for strings); kit::topn for top-k; stringi::stri_sort(numeric = TRUE) for natural order.
- Keep sparse data sparse (Matrix); matrixStats for row/col stats; never as.matrix() a big sparse, DelayedArray or BPCells matrix.
- Parallel: at most the workers in <r_env>; mirai or future multisession (portable), not mclapply on Windows; pass data explicitly.
- Plots >1e5 points: scattermore, ggrastr::rasterise() or geom_hex().
- Measure before optimising (system.time, bench::mark, profvis). More: read the high-performance-r skill.
</r_performance>
```

### 3.2 Runtime `<r_env>` section (generated; format spec)

Grammar (one section, ≤ 4 lines, placed after all stable sections):

```text
<r_env>
R <version>, <platform>, <UTF-8|NON-UTF-8> locale[, PCRE JIT]; <n> cores (use <= <k> workers); RAM <total> GB (<avail> GB free)
Installed: <cat>: <pkg> <major.minor[.patch]>, ...; <cat>: ...
[Installed but NOT loadable (do not library() them): <pkg> (<short reason>); ...]
Not installed (ask before installing; Bioc = BiocManager, GitHub = remotes): <pkg>[<repo if not CRAN>], ...
</r_env>
```

Rules: versions shortened by `sub("^(\\d+\\.\\d+(\\.\\d+)?).*$", "\\1", gsub("-", ".", v))`;
`k` = explicit option, else 2 if `_R_CHECK_LIMIT_CORES_` is set, else
`parallelly::availableCores(omit = 1)` if installed, else `max(1, detectCores() - 1)`; load-failure
reasons shortened to "missing system library <file>" / "missing dependency <pkg>" / first 60 chars.
Actual output on this machine (executed, `$W/out_proto_caps_prompt.txt`; 866 chars ≈ 217 tokens):

```text
<r_env>
R 4.4.3, aarch64-apple-darwin20, UTF-8 locale; 8 cores (use <= 7 workers); RAM 24 GB (6 GB free)
Installed: io+wrangle: data.table 1.18.2; io: vroom 1.7.1, readr 2.2.0; io+disk: arrow 23.0.1; wrangle: dplyr 1.2.1, dtplyr 1.3.3; stats: matrixStats 1.5.0; strings: stringi 1.8.7, stringr 1.6.0; matrix: Matrix 1.7.5, DelayedArray 0.32.0, HDF5Array 1.34.0; parallel: future 1.70.0, future.apply 1.20.2, BiocParallel 1.40.2; profile: profvis 0.4.0; plot: ggplot2 4.0.2, scattermore 1.2, ggrastr 1.0.2; sc: Seurat 5.4.0, SeuratObject 5.4.0, SingleCellExperiment 1.28.1
Installed but NOT loadable (do not library() them): BPCells (missing system library libhdf5.310.dylib)
Not installed (ask before installing; Bioc = BiocManager, GitHub = remotes): nanoparquet, duckdb, duckplyr, collapse, tidytable, kit, qs2, fst, bigmemory, mirai, crew, targets, bench
</r_env>
```

### 3.3 Registry of steered packages (ship as internal data, e.g. `R/sysdata.rda` or a table in code)

| pkg | cat | repo | role |
|---|---|---|---|
| data.table | io+wrangle | CRAN | fread/fwrite, fast grouped ops, in-place := |
| vroom | io | CRAN | lazy fast delimited reader |
| arrow | io+disk | CRAN | CSV/Parquet/Feather, open_dataset |
| readr | io | CRAN | tidyverse CSV reader |
| nanoparquet | io | CRAN | dependency-free Parquet |
| duckdb | disk | CRAN | SQL on files, larger than memory |
| duckplyr | disk | CRAN | dplyr on duckdb |
| collapse | wrangle | CRAN | fast grouped stats |
| dplyr | wrangle | CRAN | tidy verbs |
| dtplyr | wrangle | CRAN | dplyr to data.table |
| tidytable | wrangle | CRAN | tidy verbs on data.table |
| matrixStats | stats | CRAN | row/col stats |
| kit | stats | CRAN | topn, parallel pmin/psum |
| stringi | strings | CRAN | ICU strings, natural sort |
| stringr | strings | CRAN | tidy strings on stringi |
| qs2 | serialize | CRAN | fast object files |
| fst | serialize | CRAN | fast data.frame files |
| Matrix | matrix | CRAN | sparse matrices |
| bigmemory | matrix | CRAN | file-backed matrices |
| DelayedArray | matrix | Bioc | block-processed arrays |
| HDF5Array | matrix | Bioc | on-disk HDF5 arrays |
| BPCells | matrix | GitHub | on-disk single-cell matrices |
| mirai | parallel | CRAN | async workers |
| future | parallel | CRAN | futures API |
| future.apply | parallel | CRAN | future_lapply |
| crew | parallel | CRAN | worker controllers (targets) |
| BiocParallel | parallel | Bioc | Bioc parallel back-ends |
| targets | pipeline | CRAN | cached pipelines |
| bench | profile | CRAN | benchmarking |
| profvis | profile | CRAN | profiling |
| ggplot2 | plot | CRAN | grammar of graphics |
| scattermore | plot | CRAN | rasterised scatter |
| ggrastr | plot | CRAN | rasterise ggplot layers |
| Seurat | sc | CRAN | single-cell analysis |
| SeuratObject | sc | CRAN | Seurat v5 layers |
| SingleCellExperiment | sc | Bioc | Bioc single-cell container |

Not in the registry on purpose: polars (not on CRAN), qs (archived), disk.frame (archived), fs/brio/
digest (not needed for steering).

### 3.4 The `high-performance-r` skill (ship as `inst/skills/high-performance-r/`)

Frontmatter validated against Pi's rules (name matches `^[a-z0-9]+(-[a-z0-9]+)*$`, 18 chars;
description 537 chars ≤ 1024). Sizes: SKILL.md 232 lines / ~15.3 KB (~3.8k tokens);
`references/parallel-and-pipelines.md` ~3.7 KB; `references/single-cell.md` ~2.9 KB.
All 18 ```` ```r ```` blocks were extracted and executed in fresh R processes: 18/18 ran without an
R error (`$W/test_skill_recipes.R`, output in §5.15). **Verifier correction:** "no R error" was not
"correct": the original mirai recipe (`mirai_map(1:8, function(i, k) i^k, k = 2)[]`) returned 8
`miraiError` values ("argument "k" is missing"), because mirai returns task errors as values and its
named `...` objects are free variables of `.f`, not arguments. The recipe below now uses
`.args = list(k = 2)` (re-run: `1 4 9 … 64`, no errors). Two further fixes below: `qd_save()`
drops (not refuses) language objects, and the duckplyr limit is 1e6 cells. The plotting block only
saves `p1`; `p2`/`p3` were additionally rendered with `ggsave()` during verification (all fine).
Source files: `$W/skill/high-performance-r/` (still contain the uncorrected text).

#### 3.4.1 `SKILL.md`

````markdown
---
name: high-performance-r
description: Pick fast, memory-safe R tools for big data work in a live R session - CSV/Parquet I/O, larger-than-memory queries (duckdb, arrow), grouped statistics, joins, strings/regex, sorting/top-n, saving objects (qs2, RDS, fst), sparse and on-disk matrices, parallel workers (mirai, future), targets pipelines, profiling, plotting millions of points, and single-cell (Seurat v5 + BPCells, SingleCellExperiment). Use when data has more than about 1e6 rows or 100 MB, a step takes more than about 10 s, memory is tight, or the user asks for speed.
---

# High-performance R

You are working inside the user's live R session. The objects in memory are the asset:
a 5 GB object may have taken minutes to build. Every rule below serves two goals: finish
fast, and never lose or duplicate what is already in memory.

## Ground rules

1. **Use what is installed.** The `<r_env>` section lists installed packages. Use them
   opportunistically; if the best tool is missing, use the base-R fallback from the table
   and *mention* the faster option. Never run `install.packages()`, `BiocManager::install()`,
   `remotes::install_*()` or `update.packages()` without the user's explicit yes (see
   "Installing" at the end).
2. **Look before you load or print.** `dim(x)`, `nrow(x)`, `object.size(x)`, `file.size(path)`,
   `str(x, max.level = 1)`, `head(x)`. Never print a whole large object into the transcript.
3. **Do not copy big objects.** `y <- x; y$col <- ...` copies `x` on write. Prefer
   `data.table` in-place updates (`:=`, `set()`, `setorder()`, `setnames()`), work on column
   subsets, and `rm(tmp); invisible(gc())` large temporaries.
4. **Probe before `library()` of an unloaded compiled package** when the session holds
   valuable objects: `callr::r(function() loadNamespace("pkg"))` (or `processx`) first.
   On R < 4.6.1 one failed `dyn.load()` with a long error can corrupt the session so the
   *next* package load crashes R.
5. **Measure.** `system.time()` for one-off timing, `bench::mark()` to compare, `profvis`
   to find hotspots. Optimise the slowest step only.
6. **Threads and workers.** Stay within the worker count in `<r_env>`. data.table, arrow,
   duckdb and qs2 are already multi-threaded; do not also run them inside parallel workers
   without lowering their threads (`data.table::setDTthreads(1)`,
   `DBI::dbExecute(con, "SET threads = 1")`, `qs2` `nthreads = 1`).

## Decision table

| Task | Best tool (if installed) | Prefer when | Base-R fallback |
|---|---|---|---|
| Read CSV/TSV | `data.table::fread()` | general default; auto-detects types, multi-threaded | `read.csv(colClasses=, nrows=)` |
| | `arrow::read_csv_arrow()` | fastest on big files; also need Parquet later | |
| | `vroom::vroom()` | only a few columns will be touched (lazy ALTREP) | |
| | `readr::read_csv()` | tidyverse-consistent parsing; small/medium files | |
| Write CSV | `data.table::fwrite()` | always (about 30x faster than `write.csv`) | `write.csv(row.names = FALSE)` |
| Read a window of a huge text file | `vroom::vroom_lines(skip=, n_max=)` | random access deep into a file | `readLines(con, n=)` on an open connection |
| Parquet read/write | `arrow::read_parquet()`/`write_parquet()` | nested types, datasets, cloud | none (use CSV or RDS) |
| | `nanoparquet::read_parquet()`/`write_parquet()` | flat tables, zero dependencies | |
| Query data larger than RAM | `duckdb` SQL on `read_parquet()`/`read_csv_auto()` | joins/aggregations over files; spills to disk | loop over chunks with `read.csv(skip=, nrows=)` |
| | `arrow::open_dataset()` + dplyr verbs + `collect()` | partitioned Parquet directories | |
| | `duckplyr` (`read_parquet_duckdb()`) | user wants dplyr syntax on duckdb | |
| In-memory wrangling | `data.table` | >1e6 rows, joins, in-place updates, grouped ops | `split()`/`lapply()`, `merge()`, `aggregate()` |
| | `collapse` | fastest grouped statistics, low overhead | `rowsum()`, `tapply()` |
| | `dplyr` (+ `dtplyr`/`tidytable` backends) | readability; <1e6 rows or few groups | |
| Grouped statistics | `collapse::fmean(x, g)`, data.table `dt[, .(m = mean(x)), by = g]` | many groups | `rowsum(x, g) / tabulate(g)`, `tapply()` |
| Matrix row/col stats | `matrixStats::colMedians()`, `colSds()`; `collapse::fsd()` | dense numeric matrices | `colMeans()`, `rowSums()` (fast); `apply()` (slow) |
| Strings | `stringi` (`stri_detect_fixed`, `stri_replace_all_fixed`, `stri_trans_general`) | Unicode-correct ops, locales, transliteration | `grepl(fixed = TRUE)`, `gsub(perl = TRUE)`, `startsWith()` |
| Regex search | base `grepl(pattern, x, perl = TRUE)` | regex over many strings (fastest here) | same (avoid default TRE engine: roughly 5-75x slower, pattern-dependent) |
| Sort | `order(x, method = "radix")`, `data.table::setorder()` (in place) | numbers, factors, byte-order strings | `order()` |
| Locale/natural sort | `stringi::stri_sort(x, numeric = TRUE)`, `stri_order(x, locale = "en")` | file names like `file2 < file10` | `order()` (locale collation, slow) |
| Top-k of a large vector | `kit::topn(x, k)` | k much smaller than n | `sort(x, partial = n - k + 1)` or `order(x, decreasing = TRUE)[1:k]` |
| Save/load R objects | `qs2::qs_save()`/`qs_read()` | any object; fast, compact, multi-threaded | `saveRDS(x, f, compress = FALSE)` (fast, large) |
| | `qs2::qd_save()`/`qd_read()` | plain data (no formulas/closures) | `saveRDS()` (gzip, slow to write) |
| | `fst::write_fst()`/`read_fst(columns=, from=, to=)` | data frames, read a column/row subset | |
| Sparse matrices | `Matrix` (`dgCMatrix`) | mostly zeros (single-cell, text) | dense `matrix` only if small |
| Larger-than-RAM matrices | `DelayedArray`/`HDF5Array`, `BPCells`, `bigmemory` | on-disk, block-wise processing | process column blocks from files |
| Parallel map | `mirai::mirai_map()`, `future.apply::future_lapply()`, `furrr` | portable, all OSes | `parallel::parLapply()` (PSOCK), `mclapply()` (Unix only) |
| Bioconductor parallel | `BiocParallel::bplapply(BPPARAM = SnowParam(n))` | Bioc functions take `BPPARAM` | `parallel` |
| Multi-step pipeline with caching | `targets` (+ `crew` workers) | long pipelines re-run after edits | scripts + `saveRDS()` checkpoints |
| Profile / benchmark | `profvis::profvis()`, `bench::mark()` | find hotspots, compare options with memory | `Rprof()` + `summaryRprof()`, `system.time()` |
| Plot >1e5 points | `scattermore::geom_scattermore()`, `ggrastr::rasterise()`, `geom_hex()` | millions of points, vector output | `png()` + `plot(pch = ".")`, `smoothScatter()` |
| Single-cell | Seurat v5 layers + BPCells on disk; SingleCellExperiment + HDF5Array | >100k cells | `Matrix` sparse |

Not recommended by default: `polars` (not on CRAN; R-multiverse only), `qs` (archived on
CRAN 2026-01-17; its `.qs` files are not readable by qs2), `disk.frame` (archived).

## Recipes

### Delimited files
```r
path <- tempfile(fileext = ".csv")
df <- data.frame(id = 1:1e5, g = sample(letters, 1e5, TRUE), x = runif(1e5))
data.table::fwrite(df, path)                       # write
dt <- data.table::fread(path)                      # read everything
dt2 <- data.table::fread(path, select = c("g", "x"), nrows = 1000)   # columns / first rows only
tb <- arrow::read_csv_arrow(path, col_select = c("id", "x"))
peek <- readLines(path, n = 5)                     # look at the head before parsing
```

### Parquet and queries on files (larger than memory)
```r
pq <- tempfile(fileext = ".parquet")
df <- data.frame(g = sample(letters, 1e5, TRUE), k = sample(1:100, 1e5, TRUE), x = runif(1e5))
arrow::write_parquet(df, pq)                       # or nanoparquet::write_parquet(df, pq)
small <- nanoparquet::read_parquet(pq)             # flat tables, zero dependencies
# duckdb: SQL straight on the file, nothing loaded until the result
con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", file.path(tempdir(), "duckdb_tmp")))  # spill location
res <- DBI::dbGetQuery(con, sprintf(
  "SELECT g, avg(x) AS mean_x, count(*) AS n FROM read_parquet('%s') WHERE k > 50 GROUP BY g ORDER BY g", pq))
DBI::dbDisconnect(con, shutdown = TRUE)
# arrow datasets: lazy dplyr pipeline, collect() at the end
library(dplyr)
res2 <- arrow::open_dataset(pq) |> filter(k > 50) |> group_by(g) |>
  summarise(mean_x = mean(x), n = n()) |> collect()
```
Partitioned output: `arrow::write_dataset(df, dir, partitioning = "g")`; read it back with
`arrow::open_dataset(dir)`. duckdb uses up to 80% of RAM by default; lower it with
`SET memory_limit = '4GB'` when the R session itself holds large objects.

### data.table idioms (fast and in place)
```r
library(data.table)
dt <- data.table(g = sample(1e4, 1e6, TRUE), x = rnorm(1e6), y = runif(1e6))
agg <- dt[, .(m = mean(x), s = sum(y), n = .N), by = g]    # GForce: keep mean/sum unqualified
dt[, z := x * 2]                                           # add a column without copying
dt[x < 0, x := 0]                                          # conditional update in place
setorder(dt, g, -x)                                        # sort in place
setkey(dt, g); lookup <- data.table(g = 1:10, label = letters[1:10], key = "g")
joined <- lookup[dt, on = "g", nomatch = NULL]             # inner join
wide <- dcast(agg[g <= 5], . ~ g, value.var = "m")
```
Check the optimisation with `dt[, .(m = mean(x)), by = g, verbose = TRUE]` ("GForce optimized j").
Writing `base::mean(x)` or `stats::median(x)` in `j` turns GForce off (measured up to 36x slower).

### collapse (fastest grouped statistics)
```r
library(collapse)                                   # attach it: fsummarise needs unqualified names
df <- data.frame(g = sample(1e4, 1e6, TRUE), h = sample(letters, 1e6, TRUE), x = rnorm(1e6))
m1 <- fmean(df$x, g = df$g)                         # vector API, named by group
out <- df |> fgroup_by(g, h) |> fsummarise(mx = fmean(x), n = fnobs(x))
```
`collapse::fsummarise(..., m = collapse::fmean(x))` with the `collapse::` prefix inside is
evaluated group by group (measured 100x slower on 250k groups).

### Strings and regex
```r
x <- c("file10.R", "file2.R", "File1.R", "naïve.R")
hit_fixed <- grepl(".R", x, fixed = TRUE)           # literal
hit_re    <- grepl("^file[0-9]+\\.R$", x, perl = TRUE, ignore.case = TRUE)
first_pos <- regexpr("[0-9]+", x, perl = TRUE)      # prefer regexpr over gregexpr on big vectors
stringi::stri_sort(x, numeric = TRUE)               # natural order: File1, file2, file10
stringi::stri_trans_general("naïve", "Latin-ASCII") # "naive"
```

### Sorting and top-k
```r
x <- runif(1e6); s <- sprintf("id_%06d", sample(1e6))
o  <- order(x, method = "radix")
os <- order(s, method = "radix")                    # fast, byte order (C locale), not dictionary order
top <- kit::topn(x, 10L)                            # indices of the 10 largest
top_base <- order(x, decreasing = TRUE)[1:10]       # fallback
```

### Saving objects
```r
obj <- list(df = data.frame(a = 1:10), fit = lm(mpg ~ wt, mtcars))
f <- tempfile(fileext = ".qs2")
qs2::qs_save(obj, f, nthreads = 2)                  # any R object
obj2 <- qs2::qs_read(f, nthreads = 2)
qs2::qs_to_rds(f, sub("qs2$", "rds", f))            # convert to plain RDS when sharing
saveRDS(obj, tempfile(fileext = ".rds"), compress = FALSE)   # base: fast write, larger file
```
`qd_save()` silently drops language objects (formulas, calls, model terms) with only a warning;
the file is still written and a model fit comes back broken. Use `qs_save()` for model fits. RDS with default gzip is slow to write for big objects (measured about 20x
slower than `qs2` with 4 threads on a 50 MB data frame).

### Matrices
```r
library(Matrix)
sp <- rsparsematrix(20000, 5000, density = 0.02)    # never as.matrix() this
cs <- colSums(sp); rm_ <- rowMeans(sp)              # Matrix methods stay sparse
m <- matrix(rnorm(1e6), 1000)
med <- matrixStats::colMedians(m)                    # vs apply(m, 2, median)
sds <- matrixStats::colSds(m)
```

### Parallel work
See `references/parallel-and-pipelines.md` (mirai, future, BiocParallel, targets + crew,
thread oversubscription, library paths in workers).

### Profiling
```r
f <- function(n) { x <- numeric(0); for (i in 1:n) x <- c(x, i); sum(x) }
g <- function(n) sum(seq_len(n))
print(system.time(f(2e4)))
b <- bench::mark(f(2e4), g(2e4), check = TRUE, min_iterations = 3)
print(b[, c("expression", "median", "mem_alloc")])
# p <- profvis::profvis(f(5e4))   # interactive flame graph (opens a viewer)
```

### Plotting many points
```r
library(ggplot2)
d <- data.frame(x = rnorm(1e6), y = rnorm(1e6))
p1 <- ggplot(d, aes(x, y)) + scattermore::geom_scattermore(pointsize = 1, pixels = c(1000, 1000))
p2 <- ggplot(d, aes(x, y)) + ggrastr::rasterise(geom_point(size = 0.1), dpi = 150)
p3 <- ggplot(d, aes(x, y)) + geom_hex(bins = 100)    # needs the hexbin package
ggsave(tempfile(fileext = ".png"), p1, width = 5, height = 5, dpi = 100)
```

### Single-cell
See `references/single-cell.md` (Seurat v5 layers, BPCells on-disk counts, sketching,
SingleCellExperiment + HDF5Array/DelayedArray, `future.globals.maxSize`).

## Pitfalls that cost the most time

- `pkg::fun` inside `data.table` `j` or `collapse::fsummarise` disables the fast path.
- `order()` / `sort()` on character vectors without `method = "radix"` uses locale collation
  (40x slower on 1e6 strings); radix gives byte order (`"B" < "a"`).
- Default regex engine (TRE) on 1e5+ strings: use `perl = TRUE` or `fixed = TRUE`.
- `gregexpr()` on big vectors allocates heavily; use `regexpr()` or `grepl()` if one match suffices.
- `object.size()` over-counts shared and ALTREP objects (`1:1e9` reports 3.7 GB); `lobstr::obj_size()` is accurate but slower.
- `vroom()` returns lazy (ALTREP) columns: the read is fast, the first full pass pays the parsing cost.
- `saveRDS()` default gzip is slow on big objects; `compress = FALSE` or `qs2`.
- Building a result with `x <- c(x, new)` or `paste0(acc, piece)` in a loop is quadratic; collect pieces in a pre-sized list/vector and combine once.
- `mclapply()`/`plan(multicore)` forks: unavailable on Windows, discouraged in RStudio/GUIs.
- Worker processes do not see `.libPaths()` changes made in the session; set `R_LIBS` before starting workers or call `.libPaths()` on each worker.
- `future` refuses to export globals over 500 MiB (`options(future.globals.maxSize = ...)`); sending a big object to workers costs seconds per 100 MB. Prefer workers that read the data from disk themselves.
- duckdb writes spill files to `.tmp` in the working directory when memory runs out; set `temp_directory`.
- `duckplyr::read_parquet_duckdb()` returns a "prudent" lazy frame: `nrow()`, printing or other
  implicit materialisation of more than 1,000,000 cells (rows x columns, e.g. 125,000 rows of an
  8-column table) is an error; aggregate first, then `collect()`.

## Installing (only after the user says yes)

| Source | Command |
|---|---|
| CRAN | `install.packages("duckdb")` |
| Bioconductor (`DelayedArray`, `HDF5Array`, `SingleCellExperiment`, `BiocParallel`) | `BiocManager::install("HDF5Array")` |
| BPCells (GitHub / R-universe, needs HDF5 system library) | `install.packages("BPCells", repos = c("https://bnprks.r-universe.dev", "https://cloud.r-project.org"))` |
| polars (R-multiverse) | `install.packages("polars", repos = "https://community.r-multiverse.org")` |

After installing, re-check `<r_env>` (gptr refreshes it) and prefer binary packages on
Windows and macOS (`type = "binary"` is the default there).
````

#### 3.4.2 `references/parallel-and-pipelines.md`

````markdown
# Parallel workers and pipelines

## Choose a back-end

| Need | Use | Notes |
|---|---|---|
| Map a function over inputs, any OS | `mirai::daemons(n)` + `mirai::mirai_map(x, f, ...)[]` | low per-task overhead; `purrr::map(x, in_parallel(f))` (purrr >= 1.1.0, needs the `carrier` package) uses the same daemons |
| Code that already uses futures (Seurat, furrr, future.apply) | `future::plan(future::multisession, workers = n)` | `future.mirai::mirai_multisession` is a faster drop-in plan |
| Base R only | `cl <- parallel::makeCluster(n); parallel::parLapply(cl, x, f); parallel::stopCluster(cl)` | PSOCK works on every OS |
| Fork on Linux/macOS terminal only | `parallel::mclapply(x, f, mc.cores = n)` | fastest start-up; not on Windows; unsafe in RStudio/GUIs and after multi-threaded code |
| Bioconductor functions with `BPPARAM` | `BiocParallel::SnowParam(n)` (all OS) or `MulticoreParam(n)` (Unix) | |
| Cached multi-step pipeline | `targets` + `crew::crew_controller_local(workers = n)` | re-runs only outdated steps |

Measured on an 8-core laptop (loaded machine, indicative only): starting 4 workers took
about 0.3 s (PSOCK), 0.8 s (mirai with dispatcher, future multisession) and 0.02 s
(fork); 200 tiny tasks on warm workers took 1-60 ms; sending an 80 MB data frame to 4
workers took 1.4-2.4 s. So: start workers once, reuse them, and send data once.

## Rules

- Worker count: stay within `<r_env>`; leave one core for the session. Under
  `R CMD check` use at most 2.
- Do not nest parallelism: inside workers set `data.table::setDTthreads(1)`, arrow
  `arrow::set_cpu_count(1)`, duckdb `SET threads = 1`, qs2 `nthreads = 1`.
- Pass what the function needs explicitly (`mirai_map(x, f, big = big)`,
  `in_parallel(f, big = big)`); workers do not see the session's global environment.
  Named `...` objects become free variables of `f`, not arguments: write `f <- function(i) g(i, big)`;
  constant *arguments* go in `mirai_map(x, f, .args = list(k = 2))`.
- mirai returns task errors as values (`miraiError`), not as R errors: collect with `[.stop]`
  (or check `mirai::is_error_value()`) so a failure is not mistaken for a result.
- Workers are fresh R processes: they do not inherit `.libPaths()` changes made at run time.
  Before starting them: `Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))`.
- Large shared inputs: write once to disk (Parquet/qs2) and let each worker read its slice,
  instead of serialising the object to every worker.
- `future` blocks globals above 500 MiB: `options(future.globals.maxSize = 8 * 1024^3)` only
  if memory allows (each worker gets a copy).
- Always shut down: `mirai::daemons(0)`, `parallel::stopCluster(cl)`, `future::plan(future::sequential)`.

## Recipes

```r
# mirai
mirai::daemons(2)
sq <- mirai::mirai_map(1:8, function(i, k) i^k, .args = list(k = 2))[.stop]   # list of results; errors stop
mirai::everywhere(library(stats))                             # set up each worker
mirai::daemons(0)
```

```r
# future + future.apply
future::plan(future::multisession, workers = 2)
r <- future.apply::future_lapply(1:8, function(i) i^2, future.seed = TRUE)
future::plan(future::sequential)
```

```r
# base R, portable
cl <- parallel::makeCluster(2)
parallel::clusterExport(cl, character(0))                     # export what workers need
r <- parallel::parLapply(cl, 1:8, function(i) i^2)
parallel::stopCluster(cl)
```

```r
# BiocParallel
r <- BiocParallel::bplapply(1:8, function(i) i^2, BPPARAM = BiocParallel::SnowParam(2))
```

```r
# targets: write _targets.R in the project, then run tar_make()
dir <- tempfile(); dir.create(dir); old <- setwd(dir)
writeLines(c(
  'library(targets)',
  'tar_option_set(packages = "stats")',
  'list(',
  '  tar_target(raw, data.frame(x = rnorm(100), g = sample(letters[1:3], 100, TRUE))),',
  '  tar_target(fit, lm(x ~ g, data = raw)),',
  '  tar_target(summary_tbl, coef(summary(fit)))',
  ')'), "_targets.R")
targets::tar_make(reporter = "silent")
res <- targets::tar_read(summary_tbl)
setwd(old)
# parallel targets: tar_option_set(controller = crew::crew_controller_local(workers = 2))
```
````

#### 3.4.3 `references/single-cell.md`

````markdown
# Single-cell at scale

The Seurat or SingleCellExperiment object in the session may have taken minutes to load.
Never reload it, never `as.matrix()` its counts, and never `print()` it whole. Check with
`dim(obj)`, `Assays(obj)`, `Layers(obj)`, `object.size(obj)`.

## Seurat v5

- Assays are v5 `Assay5` objects with **layers** (`counts`, `data`, `scale.data`, or one
  layer per sample after splitting). Access: `LayerData(obj, assay = "RNA", layer = "counts")`
  or `obj[["RNA"]]$counts`.
- Split by sample for integration, then join:
  `obj[["RNA"]] <- split(obj[["RNA"]], f = obj$sample)` ... `IntegrateLayers(obj, method = CCAIntegration, ...)` ... `obj <- JoinLayers(obj)`.
- Very large data: `SketchData(obj, ncells = 50000, method = "LeverageScore", sketched.assay = "sketch")`,
  analyse the sketch, then `ProjectData()` back to all cells.
- On-disk counts with **BPCells** (not on CRAN; check `<r_env>` says it is loadable):
  ```r
  # BPCells::write_matrix_dir(mat = counts, dir = "counts_bp")   # once, dgCMatrix -> bit-packed on disk
  # counts_disk <- BPCells::open_matrix_dir(dir = "counts_bp")
  # obj <- SeuratObject::CreateSeuratObject(counts = counts_disk)
  # obj[["RNA"]]$counts <- as(obj[["RNA"]]$counts, "dgCMatrix")   # back to memory if small enough
  ```
- Seurat parallelises some steps with `future`; with large objects raise
  `options(future.globals.maxSize = ...)` only when RAM allows (every worker receives a copy).

```r
# small, runnable illustration of v5 layers
library(Seurat)
set.seed(1)
m <- Matrix::rsparsematrix(2000, 600, density = 0.05); m@x <- abs(round(m@x * 10)) + 1
rownames(m) <- paste0("g", 1:2000); colnames(m) <- paste0("c", 1:600)
obj <- CreateSeuratObject(counts = m)
obj$sample <- rep(c("a", "b"), each = 300)
obj[["RNA"]] <- split(obj[["RNA"]], f = obj$sample)
print(Layers(obj))                        # counts.a, counts.b
obj <- JoinLayers(obj)
print(Layers(obj))                        # counts
obj <- NormalizeData(obj, verbose = FALSE)
```

## SingleCellExperiment + on-disk arrays (Bioconductor)

```r
library(SingleCellExperiment)
m <- Matrix::rsparsematrix(1000, 300, density = 0.05); m@x <- abs(m@x)
sce <- SingleCellExperiment(assays = list(counts = m))
h5 <- tempfile(fileext = ".h5")
disk <- HDF5Array::writeHDF5Array(counts(sce), filepath = h5, name = "counts", as.sparse = TRUE)
DelayedArray::setAutoBlockSize(1e8)       # block size in bytes for block processing
cs <- DelayedArray::colSums(disk)         # computed block by block from disk
d <- tempfile()
HDF5Array::saveHDF5SummarizedExperiment(sce, d)      # whole object, assays on disk
sce2 <- HDF5Array::loadHDF5SummarizedExperiment(d)   # counts(sce2) is an HDF5Matrix
```

## Plotting cells

`DimPlot()`/`FeaturePlot()` with >1e5 cells: add `raster = TRUE` (Seurat rasterises
automatically above 1e5 cells) or build with `scattermore::geom_scattermore()`.
````

Note: the BPCells block is commented out because BPCells could not be loaded on this machine;
function names were verified from the installed `NAMESPACE`
(`export(open_matrix_dir)`, `export(write_matrix_dir)`, `export(write_matrix_memory)`, …) and from the
Seurat BPCells vignette (https://satijalab.org/seurat/articles/seurat5_bpcells_interaction_vignette).

### 3.5 Constants and thresholds (recommended)

| Constant | Value | Evidence |
|---|---|---|
| UI full-text re-render throttle | every ≥ 50 deltas or ≥ 100 ms | §2.4.2 (13 s vs 96 ms per 5,000 deltas) |
| stream buffer initial size / growth | 256 slots, doubling | §2.4.2 |
| binary-file sniff | first 8,000 bytes contain `00` → binary | §2.4.4 (0.20 s for 2,019 files) |
| grep: skip files larger than | 2 MB default (configurable) | §2.4.4 |
| "big data" steering threshold in prompts | 1e6 rows / 100 MB / 10 s | §2.3 ratios become >5x at these sizes |
| load probe concurrency / timeout | 2 processes / 60 s | §2.5 |
| worker cap under check | 2 (`_R_CHECK_LIMIT_CORES_`) | CRAN policy; parallelly behaviour |

### 3.6 CRAN policy text relied on (verbatim, https://cran.r-project.org/web/packages/policies.html)

- "If running a package uses multiple threads/cores it must never use more than two simultaneously".
- "Packages should not write in the user's home filespace (including clipboards), nor anywhere else
  on the file system apart from the R session's temporary directory".
- "For R version 4.0 or later … packages may store user-specific data, configuration and cache files
  in their respective user directories obtained from tools::R_user_dir()" (keep sizes small, prune).
- "A package listed in 'Suggests' or 'Enhances' should be used conditionally in examples or tests if
  it cannot straightforwardly be installed on the major R platforms."
- "Compiled code should never terminate the R process within which it is running."

---

## 4. Recommended design for gptr

### 4.1 Prompt integration (Pi parity)

- Add two system-prompt sections to the section registry (D-26/REQ-31):
  `r_performance` (static text of §3.1; editable/removable like any section) and `r_env`
  (generated, §3.2). Order: `preamble`, `tools`, `rules`, `r_performance`, `project_context`,
  `skills`, `cwd`, **`r_env` last** so its changes do not invalidate the cached prompt prefix.
- Alternatively (equivalent), attach the shortest rules as `promptGuidelines` of the `r` tool, e.g.
  `"Use only packages listed in <r_env>; ask before installing any package."` and
  `"Never print whole large objects; check dim()/object.size() first."`, and keep the rest in
  `r_performance`.
- Register the `high-performance-r` skill as a built-in skill in `inst/skills/`, listed in
  `<skills>` exactly as Pi does (name, description, location), so the model reads it on demand.
- When packages change (after an install, after `library()` of a new package, or on `/env`),
  recompute `r_env` and send a section patch (Pi `diffSystemPromptSections` semantics), not a new
  system prompt.

### 4.2 Capability detection API

```r
gptr_capabilities(registry = NULL, check_load = FALSE, refresh = FALSE)
#> data.frame: pkg, cat, repo, role, version, compiled ("yes"/"no"), built, path,
#>             installed, loaded, loadable (TRUE/FALSE/NA), load_error
#> attr "session": list(r, platform, os, utf8, cores, ram_gb, ram_free_gb, pcre_jit)
```

Algorithm (prototype in §5.12, executed):
1. `paths <- find.package(pkgs, quiet = TRUE)`; for each path `readRDS(file.path(path, "Meta",
   "package.rds"))$DESCRIPTION[c("Version", "NeedsCompilation", "Built")]`. Never
   `requireNamespace()`, `rlang::is_installed()` or `installed.packages()`.
2. `loaded <- pkg %in% loadedNamespaces()` → `loadable = TRUE`.
3. Pure-R packages (`NeedsCompilation == "no"`) are assumed loadable.
4. `check_load = TRUE` (default FALSE; run in the background at session start when
   `getRversion() < "4.6.1"`, or on demand before the agent `library()`s a compiled package):
   probe each installed, compiled, not-loaded package in its **own** child `Rscript --vanilla -e
   'loadNamespace(p)'` via `processx::process$new()`, 2 at a time, 60 s timeout, with
   `env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))`.
5. Cache in memory for the session; optionally persist probe results under
   `tools::R_user_dir("gptr", "cache")` keyed by `pkg + version + Built + path` (only after the
   D-10 consent to create user dirs).
6. Session facts: `getRversion()`, `R.version$platform`, `l10n_info()[["UTF-8"]]`,
   `parallel::detectCores()`, `ps::ps_system_memory()` total/avail, `pcre_config()[["JIT"]]`.
7. `gptr_prompt_r_env(caps, max_workers = NULL)` renders §3.2.

Also add a guard in the `r` tool (REQ-09/D-11): before evaluating code that calls `library()`,
`require()` or `pkg::` on an installed-but-unloaded compiled package with `loadable = NA`, probe it
first on R < 4.6.1; if it fails, return the error to the model without touching the live session.

### 4.3 Install-consent policy

- The system prompt and skill say: never install without an explicit yes.
- Enforce it in the permission layer (D-11 advisory classifier): label calls to
  `install.packages`, `BiocManager::install`, `remotes::install_*`, `pak::pkg_install`/`pak::pak`,
  `devtools::install*`, `update.packages`, `remove.packages`, `utils::install.packages` as
  **"modifies the R library"**, requiring approval in every mode except fully autonomous; in `plan`
  mode block them.
- After an approved install, refresh `r_env` (§4.1).

### 4.4 Harness internals (what to build, with the measured reason)

| Area | Decision | Reason (section) |
|---|---|---|
| JSON parse | `jsonlite::parse_json()` (= `fromJSON(simplifyVector = FALSE)`) for SSE events and responses | 5–11 µs/event (§2.4.1); preserves arrays as lists |
| JSON serialise | serialise each message once when created (`toJSON(auto_unbox = TRUE, null = "null", digits = NA)`), store as class `"json"`; build bodies with `json_verbatim = TRUE`; send with `httr2::req_body_raw(body, "application/json")` | ~10–55x faster per turn, identical bytes (§2.4.1) |
| Encoding | `as_utf8_deep()` before serialisation; read files with `encoding = "UTF-8"`; mark `system2`/`processx` output as UTF-8 when `validUTF8()` | C-locale corruption (§2.6) |
| Session file | append-only JSONL with a kept-open `file(path, "ab")` + `flush()` per entry; never rewrite | 12 µs vs 97 ms (§2.4.1); D-09 |
| Session load | `readLines(encoding = "UTF-8")` then `lapply(parse_json)` or one `fromJSON(paste0("[", paste(l, collapse = ","), "]"), simplifyVector = FALSE)` | ~90 ms per 5 MB (§2.4.1) |
| Streaming buffer | closure + `<<-` doubling character buffer (`stream_buffer()` in §5.13) | linear; env-callback pattern is quadratic (§2.4.2) |
| Live re-render | throttle full-text rebuilds; echo deltas with `cat()` | §2.4.2 |
| read tool | `readLines(con, n)` on an open connection; to reach an offset, skip in chunks of 50,000 lines; if `vroom` is installed and offset > ~100k lines use `vroom::vroom_lines(skip, n_max, altrep = FALSE)`; line counts only when cheap (≤ 10 MB) or via `vroom_lines` | §2.4.3 |
| grep tool | per-file loop: `file.size` limit, NUL sniff (8,000 bytes), `readLines(encoding = "UTF-8", warn = FALSE, skipNul = TRUE)`, `grepl(perl = TRUE)` (or `fixed = TRUE` for literal mode), `regexpr(perl = TRUE)` for columns; never TRE, never `gregexpr` | §2.4.4 |
| find/ls tools | `list.files(recursive = TRUE, all.files = hidden, include.dirs)` with **relative** names then `file.path()` only for results; own glob→regex (supporting `**`, `*` not crossing `/`, `?`, `{a,b}`); metadata `file.info(extra_cols = FALSE)`; sort name via `order(method = "radix")` or, if stringi present, `stri_order(numeric = TRUE)`; time/size via `order()` | §2.4.5 |
| base64 | `gsub("\n", "", jsonlite::base64_enc(raw), fixed = TRUE)` (or `openssl::base64_encode()` if openssl is Imported for auth); decode `jsonlite::base64_dec()`; splice large image strings into cached JSON | §2.4.6 |
| hashing | `rlang::hash_file()` for stale-edit detection; `rlang::hash()` for cache keys; fallback `tools::md5sum()`; on R ≥ 4.5 `tools::md5sum(bytes = charToRaw(x))` for strings | §2.4.7 |
| object inspection | `object.size()` by default (fast) with a note that it over-counts shared/ALTREP; `lobstr::obj_size()` when installed and the object is < ~1e5 elements; `str(max.level = 1, list.len = 20)` | §2.4.8 |
| workers (D-12) | set `R_LIBS` from `.libPaths()` in the child env; prefer PSOCK/processx over fork; cap workers per `<r_env>` | §2.3, §2.5 |
| Rcpp (D-21) | none for these internals | nothing measured needs it |

### 4.5 Imports vs Suggests (D-20)

Recursive hard dependencies (executed `$W/b16_deps.R`, current CRAN metadata):
`httr2` → askpass cli curl glue lifecycle magrittr openssl R6 rlang sys vctrs withr (12);
`processx` → ps R6; `jsonlite`, `cli`, `rlang`, `digest`, `yyjsonr`, `stringi`, `brio`, `fs`,
`base64enc` → 0 each; `vroom` → 21; `callr` → otel processx ps R6. **Union of httr2 + jsonlite + cli
+ processx = 16 packages.** Adding yyjsonr, stringi, digest, base64enc, brio, fs, yaml, evaluate or
S7 adds exactly 1 package each; mirai adds 2 (nanonext); later adds 2 (Rcpp); promises adds 5.

| Package | Recommendation | Why |
|---|---|---|
| jsonlite | **Imports** | only JSON library needed; fast enough with caching |
| httr2 | **Imports** (D-20) | provider HTTP |
| cli | **Imports** (D-20) | console |
| processx | **Imports** (D-20) | load probe, workers, shell |
| rlang | **Imports** (free: in httr2 tree) | `hash()`/`hash_file()` |
| ps | **Imports** (free: in processx tree) | RAM for `<r_env>` |
| openssl | Imports only if the auth tracks need it (in httr2 tree, free) | base64 encode alternative, sha256 |
| vroom | Suggests | deep read-tool windows (7–10x) |
| stringi | Suggests | natural sort in find/ls |
| lobstr | Suggests | accurate object sizes (REQ-21) |
| parallelly | Suggests | cgroup/Slurm-aware worker count |
| yyjsonr, RcppSimdJson | not used | semantic differences; gains unnecessary |
| digest, base64enc, secretbase, xxhashlite, b64, brio, fs | not used | base/rlang/jsonlite equivalents measured adequate |
| data.table, arrow, duckdb, collapse, qs2, mirai, … | **not listed** | gptr never calls them; the agent's code does, gated by `<r_env>`; skill code is not run by `R CMD check` |
| Rcpp | not used | no benchmark justifies compiled code (REQ-01) |

---

## 5. Verified R prototypes

All scripts live in `$W`. Run as `LANG=en_US.UTF-8 Rscript --vanilla <file>` unless noted. The
private library `$W/../../rlib` (= `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib`)
held CRAN binaries for R 4.4 of: bench 1.1.4, yyjsonr 0.1.21, RcppSimdJson 0.1.15, qs2 0.1.7,
collapse 2.1.6, kit 0.0.21, secretbase 1.2.0, xxhashlite 0.2.2, nanoparquet 0.4.3, duckdb 1.5.0,
duckplyr 1.2.1, nanonext 1.8.1, mirai 2.6.1, b64 0.1.7, lobstr 1.2.0, fst 0.9.8, tidytable 0.11.2,
targets 1.12.0, crew 1.3.0, bigmemory 4.6.4, future.mirai 0.10.1 (some installed by other tracks).
Nothing was installed into the user library.

### 5.1 Shared helper `common.R` (prior researcher's; re-used unchanged)

```r
PRIV <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
.libPaths(c(.libPaths(), PRIV))   # system library first, private lib as fallback
WORK <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19"
options(width = 200, digits = 4)
suppressPackageStartupMessages(library(bench))
show <- function(b, title = NULL) {
  if (!is.null(title)) cat("\n### ", title, "\n", sep = "")
  d <- data.frame(expr = as.character(b$expression),
                  min = format(b$min), median = format(b$median),
                  itr_sec = signif(b$`itr/sec`, 4),
                  mem_alloc = format(b$mem_alloc), n_itr = b$n_itr, n_gc = b$n_gc,
                  stringsAsFactors = FALSE)
  med <- as.numeric(b$median); d$rel <- signif(med / min(med), 3)
  print(d, row.names = FALSE, right = FALSE)
  invisible(b)
}
ver <- function(...) { p <- c(...); v <- vapply(p, function(x) as.character(utils::packageVersion(x)), ""); cat("versions: ", paste(p, v, collapse = ", "), "\n") }
```

### 5.2 JSON benchmark `b1_json.R` (prior researcher's script, re-run by me under UTF-8)

```r
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
ver("jsonlite", "yyjsonr", "RcppSimdJson", "bench")
set.seed(1)
words <- c("the","model","returns","a","data.frame","with","columns","gene","cluster","p_val","avg_log2FC","and","we","filter","rows","where","adjusted","p","value","is","below","0.05","then","plot","using","ggplot2","geom_point","UMAP","Seurat","object","normalised","counts","sparse","matrix","function","error","warning","été","中文","emoji \U0001F600","quote \" backslash \\ newline \n tab \t")
txt <- function(n) paste(sample(words, n, TRUE), collapse = " ")

## ---- (a) streaming SSE delta chunk (Anthropic-style content_block_delta) ~ 120 bytes
delta_json <- '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" the normalised counts are stored in a sparse matrix"}}'
## ---- (b) OpenAI-style chat.completion.chunk ~ 350 bytes
oai_chunk <- '{"id":"chatcmpl-9x8y7z","object":"chat.completion.chunk","created":1790000000,"model":"gpt-x","system_fingerprint":"fp_abc123","choices":[{"index":0,"delta":{"content":" sparse matrix"},"logprobs":null,"finish_reason":null}],"usage":null}'
## ---- (c) request body: system + 60 messages incl. tool calls/results + 6 tool schemas
tool_schema <- function(nm) list(name = nm, description = txt(40),
  input_schema = list(type = "object", properties = list(
    path = list(type = "string", description = txt(12)),
    code = list(type = "string", description = txt(12)),
    limit = list(type = "integer", description = txt(8)),
    flags = list(type = "array", items = list(type = "string"))), required = list("path")))
mk_msgs <- function(n) {
  out <- vector("list", n)
  for (i in seq_len(n)) {
    k <- i %% 4
    out[[i]] <- if (k == 1) list(role = "user", content = list(list(type = "text", text = txt(60))))
    else if (k == 2) list(role = "assistant", content = list(list(type = "text", text = txt(80)),
          list(type = "tool_use", id = sprintf("toolu_%06d", i), name = "r", input = list(code = paste0("x <- ", txt(30)), timeout = 60L))))
    else if (k == 3) list(role = "user", content = list(list(type = "tool_result", tool_use_id = sprintf("toolu_%06d", i - 1L),
          content = list(list(type = "text", text = txt(400))), is_error = FALSE)))
    else list(role = "assistant", content = list(list(type = "text", text = txt(150))))
  }
  out
}
req <- list(model = "claude-x", max_tokens = 8192L, stream = TRUE, temperature = 0.2,
            system = list(list(type = "text", text = txt(1500), cache_control = list(type = "ephemeral"))),
            tools = lapply(c("read","write","edit","r","grep","find"), tool_schema),
            messages = mk_msgs(60))
req_json <- as.character(jsonlite::toJSON(req, auto_unbox = TRUE, null = "null", digits = NA))
cat("sizes (bytes): delta =", nchar(delta_json, "bytes"), " oai_chunk =", nchar(oai_chunk, "bytes"), " request =", nchar(req_json, "bytes"), "\n")

## ---- (d) 5 MB session: JSON array document + JSONL (one entry per line)
entries <- list(); sz <- 0; i <- 0
while (sz < 5 * 1024^2) {
  i <- i + 1
  e <- list(type = "message", id = sprintf("%08x", i), parentId = if (i > 1) sprintf("%08x", i - 1L) else NULL,
            timestamp = "2026-09-29T12:00:00.000Z",
            message = mk_msgs(4)[[(i %% 4) + 1]],
            usage = list(input = 1234L, output = 321L, cacheRead = 10000L, cacheWrite = 0L, cost = list(total = 0.01234)))
  entries[[i]] <- e
  if (i %% 200 == 0) sz <- sum(nchar(vapply(entries, function(z) jsonlite::toJSON(z, auto_unbox = TRUE, null = "null"), ""), "bytes"))
}
jsonl_lines <- vapply(entries, function(z) as.character(jsonlite::toJSON(z, auto_unbox = TRUE, null = "null")), "")
doc_json <- paste0("[", paste(jsonl_lines, collapse = ","), "]")
f_jsonl <- file.path(WORK, "session.jsonl"); f_json <- file.path(WORK, "session.json")
writeLines(jsonl_lines, f_jsonl, useBytes = TRUE); writeLines(doc_json, f_json, useBytes = TRUE)
cat("session: entries =", length(entries), " jsonl bytes =", file.size(f_jsonl), " json bytes =", file.size(f_json), "\n")

yo_r <- yyjsonr::opts_read_json(obj_of_arrs_to_df = FALSE, arr_of_objs_to_df = FALSE, length1_array_asis = FALSE)
yo_w <- yyjsonr::opts_write_json(auto_unbox = TRUE)

show(bench::mark(
  jsonlite_fromJSON_simplifyFALSE = jsonlite::fromJSON(delta_json, simplifyVector = FALSE),
  jsonlite_parse_json            = jsonlite::parse_json(delta_json),
  jsonlite_fromJSON_default      = jsonlite::fromJSON(delta_json),
  yyjsonr_read_json_str          = yyjsonr::read_json_str(delta_json, opts = yo_r),
  yyjsonr_default                = yyjsonr::read_json_str(delta_json),
  simdjson_fparse                = RcppSimdJson::fparse(delta_json, max_simplify_lvl = "list"),
  simdjson_fparse_query          = RcppSimdJson::fparse(delta_json, query = "/delta/text"),
  regex_extract_text_field       = regmatches(delta_json, regexpr('(?<="text":")(?:[^"\\\\]|\\\\.)*', delta_json, perl = TRUE)),
  check = FALSE, min_iterations = 2000, max_iterations = 50000), "JSON PARSE: streaming delta chunk (128 B)")

show(bench::mark(
  jsonlite_fromJSON_simplifyFALSE = jsonlite::fromJSON(oai_chunk, simplifyVector = FALSE),
  yyjsonr_read_json_str          = yyjsonr::read_json_str(oai_chunk, opts = yo_r),
  simdjson_fparse                = RcppSimdJson::fparse(oai_chunk, max_simplify_lvl = "list"),
  check = FALSE, min_iterations = 2000, max_iterations = 50000), "JSON PARSE: OpenAI chunk (~250 B)")

# vectorised parse of 1000 chunks at once (batch drain of an SSE buffer)
chunks1000 <- rep(delta_json, 1000)
show(bench::mark(
  jsonlite_lapply        = lapply(chunks1000, jsonlite::fromJSON, simplifyVector = FALSE),
  jsonlite_concat_array  = jsonlite::fromJSON(paste0("[", paste(chunks1000, collapse = ","), "]"), simplifyVector = FALSE),
  yyjsonr_lapply         = lapply(chunks1000, yyjsonr::read_json_str, opts = yo_r),
  yyjsonr_concat_array   = yyjsonr::read_json_str(paste0("[", paste(chunks1000, collapse = ","), "]"), opts = yo_r),
  simdjson_fparse_vec    = RcppSimdJson::fparse(chunks1000, max_simplify_lvl = "list"),
  check = FALSE, min_iterations = 20), "JSON PARSE: 1000 delta chunks")

show(bench::mark(
  jsonlite_fromJSON_simplifyFALSE = jsonlite::fromJSON(req_json, simplifyVector = FALSE),
  jsonlite_fromJSON_default      = jsonlite::fromJSON(req_json),
  yyjsonr_read_json_str          = yyjsonr::read_json_str(req_json, opts = yo_r),
  simdjson_fparse                = RcppSimdJson::fparse(req_json, max_simplify_lvl = "list"),
  check = FALSE, min_iterations = 50), sprintf("JSON PARSE: request body (%d B)", nchar(req_json, "bytes")))

show(bench::mark(
  jsonlite_toJSON        = jsonlite::toJSON(req, auto_unbox = TRUE, null = "null", digits = NA),
  yyjsonr_write_json_str = yyjsonr::write_json_str(req, opts = yo_w),
  check = FALSE, min_iterations = 50), "JSON SERIALISE: request body")

small <- list(type = "tool_result", tool_use_id = "toolu_000123", content = list(list(type = "text", text = txt(100))), is_error = FALSE)
show(bench::mark(
  jsonlite_toJSON        = jsonlite::toJSON(small, auto_unbox = TRUE, null = "null"),
  yyjsonr_write_json_str = yyjsonr::write_json_str(small, opts = yo_w),
  check = FALSE, min_iterations = 2000), "JSON SERIALISE: one session entry (~700 B)")

show(bench::mark(
  jsonlite_fromJSON_doc   = jsonlite::fromJSON(doc_json, simplifyVector = FALSE),
  jsonlite_file_doc       = jsonlite::fromJSON(f_json, simplifyVector = FALSE),
  jsonlite_read_json_file = jsonlite::read_json(f_json),
  yyjsonr_doc             = yyjsonr::read_json_str(doc_json, opts = yo_r),
  yyjsonr_file            = yyjsonr::read_json_file(f_json, opts = yo_r),
  simdjson_fparse_doc     = RcppSimdJson::fparse(doc_json, max_simplify_lvl = "list"),
  simdjson_fload          = RcppSimdJson::fload(f_json, max_simplify_lvl = "list"),
  check = FALSE, min_iterations = 5), "JSON PARSE: 5 MB session as ONE JSON array")

rl <- function() readLines(f_jsonl, warn = FALSE, encoding = "UTF-8")
show(bench::mark(
  readLines_only                 = rl(),
  jsonlite_lapply_lines          = lapply(rl(), jsonlite::fromJSON, simplifyVector = FALSE),
  jsonlite_paste_to_array        = { l <- rl(); jsonlite::fromJSON(paste0("[", paste(l, collapse = ","), "]"), simplifyVector = FALSE) },
  jsonlite_stream_in             = jsonlite::stream_in(file(f_jsonl), simplifyVector = FALSE, verbose = FALSE),
  yyjsonr_lapply_lines           = lapply(rl(), yyjsonr::read_json_str, opts = yo_r),
  yyjsonr_paste_to_array         = { l <- rl(); yyjsonr::read_json_str(paste0("[", paste(l, collapse = ","), "]"), opts = yo_r) },
  yyjsonr_read_ndjson_file       = yyjsonr::read_ndjson_file(f_jsonl, type = "list"),
  simdjson_fparse_lines          = RcppSimdJson::fparse(rl(), max_simplify_lvl = "list"),
  check = FALSE, min_iterations = 5), "JSON PARSE: 5 MB session as JSONL")

show(bench::mark(
  jsonlite_toJSON_doc       = jsonlite::toJSON(entries, auto_unbox = TRUE, null = "null", digits = NA),
  jsonlite_vapply_lines     = vapply(entries, function(z) as.character(jsonlite::toJSON(z, auto_unbox = TRUE, null = "null", digits = NA)), ""),
  yyjsonr_write_doc         = yyjsonr::write_json_str(entries, opts = yo_w),
  yyjsonr_vapply_lines      = vapply(entries, function(z) yyjsonr::write_json_str(z, opts = yo_w), ""),
  check = FALSE, min_iterations = 5), "JSON SERIALISE: 5 MB session")

# correctness spot-checks that matter for a harness
a <- jsonlite::fromJSON(req_json, simplifyVector = FALSE); b <- yyjsonr::read_json_str(req_json, opts = yo_r); c <- RcppSimdJson::fparse(req_json, max_simplify_lvl = "list")
cat("\nidentical(jsonlite, yyjsonr) on request:", identical(a, b), "\n")
cat("all.equal(jsonlite, yyjsonr):", isTRUE(all.equal(a, b)), "\n")
cat("all.equal(jsonlite, simdjson):", isTRUE(all.equal(a, c)), "\n")
cat("str of tools[[1]]$input_schema$required:  jsonlite:", deparse(a$tools[[1]]$input_schema$required), " yyjsonr:", deparse(b$tools[[1]]$input_schema$required), " simdjson:", deparse(c$tools[[1]]$input_schema$required), "\n")
edge <- '{"a":[],"b":{},"c":null,"d":[1],"e":[1,2],"f":9007199254740993,"g":1.0,"h":"\\u00e9\\ud83d\\ude00","i":[1,"x",null],"j":true}'
cat("\nEDGE jsonlite:\n"); str(jsonlite::fromJSON(edge, simplifyVector = FALSE))
cat("EDGE yyjsonr (opts):\n"); str(yyjsonr::read_json_str(edge, opts = yo_r))
cat("EDGE simdjson (list):\n"); str(RcppSimdJson::fparse(edge, max_simplify_lvl = "list"))
cat("\nround-trip serialise of edge cases:\n")
x <- list(a = list(), b = structure(list(), names = character()), c = NULL, d = list(1L), e = 1:2, s = "x", n = NA, t = TRUE, u = "é\U0001F600")
cat("jsonlite: ", jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"), "\n")
cat("yyjsonr : ", yyjsonr::write_json_str(x, opts = yo_w), "\n")
```

Observed (`$W/out_b1_json.txt`, abbreviated to the decisive lines; full file in scratch):

```text
versions:  jsonlite 2.0.0, yyjsonr 0.1.21, RcppSimdJson 0.1.15, bench 1.1.4
sizes (bytes): delta = 132  oai_chunk = 238  request = 102145
session: entries = 3400  jsonl bytes = 5534095  json bytes = 5534097
### JSON PARSE: streaming delta chunk (128 B)
 jsonlite_fromJSON_simplifyFALSE  8µs     8.69µs ... rel 6.24
 jsonlite_parse_json              4.51µs  5.08µs ... rel 3.65
 jsonlite_fromJSON_default       27.31µs 29.4µs  ... rel 21.10
 yyjsonr_read_json_str            1.39µs  1.64µs ... rel 1.18
 yyjsonr_default                  1.19µs  1.39µs ... rel 1.00
 simdjson_fparse                 11.52µs 12.75µs ... rel 9.15
 regex_extract_text_field        12.91µs 13.65µs ... rel 9.79
### JSON PARSE: OpenAI chunk (~250 B)
 jsonlite 11.36µs | yyjsonr 2.01µs | simdjson 13.12µs
### JSON PARSE: 1000 delta chunks
 jsonlite_lapply 8.26ms | jsonlite_concat_array 2.46ms | yyjsonr_lapply 1.56ms | yyjsonr_concat_array 962.11µs | simdjson_fparse_vec 988.8µs
### JSON PARSE: request body (102145 B)
 jsonlite_fromJSON_simplifyFALSE 450.88µs | jsonlite_fromJSON_default 3.79ms | yyjsonr 170.93µs | simdjson 245.43µs
### JSON SERIALISE: request body
 jsonlite_toJSON 7.48ms (rel 40.9) | yyjsonr_write_json_str 182.7µs
### JSON SERIALISE: one session entry (~700 B)
 jsonlite_toJSON 93.64µs (rel 33.1) | yyjsonr 2.83µs
### JSON PARSE: 5 MB session as ONE JSON array
 jsonlite_fromJSON_doc 37ms | jsonlite_file_doc 40.6ms | jsonlite_read_json_file 41.1ms | yyjsonr_doc 12.5ms | yyjsonr_file 12.7ms | simdjson_fparse_doc 18.2ms | simdjson_fload 19.5ms
### JSON PARSE: 5 MB session as JSONL
 readLines_only 29.1ms | jsonlite_lapply_lines 92.8ms | jsonlite_paste_to_array 90.9ms | jsonlite_stream_in 484ms | yyjsonr_lapply_lines 53.5ms | yyjsonr_paste_to_array 72.5ms | yyjsonr_read_ndjson_file 17.7ms | simdjson_fparse_lines 48ms
### JSON SERIALISE: 5 MB session
 jsonlite_toJSON_doc 1.35s (34.7MB) | jsonlite_vapply_lines 1.44s | yyjsonr_write_doc 14.77ms | yyjsonr_vapply_lines 20.52ms
identical(jsonlite, yyjsonr) on request: FALSE
all.equal(jsonlite, yyjsonr): FALSE
all.equal(jsonlite, simdjson): TRUE
str of tools[[1]]$input_schema$required:  jsonlite: list("path")  yyjsonr: "path"  simdjson: list("path")
EDGE jsonlite:   $ a: list() $ b: Named list() $ c: NULL $ d:List of 1 $ e:List of 2 $ f: num 9.01e+15 $ h: chr "é😀"
EDGE yyjsonr:    $ a: list() $ b: Named list() $ c: NULL $ d: int 1 $ e: int [1:2] 1 2 $ f: chr "9007199254740993"
EDGE simdjson:   $ a: NULL $ b: NULL $ c: NULL $ d:List of 1 $ e:List of 2 $ f: num 9.01e+15
round-trip serialise of edge cases:
jsonlite:  {"a":[],"b":{},"c":null,"d":[1],"e":[1,2],"s":"x","n":null,"t":true,"u":"é😀"}
yyjsonr :  {"a":[],"b":{},"c":[],"d":[1],"e":[1,2],"s":"x","n":null,"t":true,"u":"é😀"}
```

### 5.3 Request assembly and JSONL append `b1b_json_extra.R`

```r
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
ver("jsonlite", "httr2")
set.seed(1)
words <- c("the","model","returns","a","data.frame","with","columns","gene","cluster","p_val","avg_log2FC","é","中文","quote \" backslash \\ newline \n tab \t")
txt <- function(n) paste(sample(words, n, TRUE), collapse = " ")
mk_msg <- function(i) {
  k <- i %% 4
  if (k == 1) list(role = "user", content = list(list(type = "text", text = txt(60))))
  else if (k == 2) list(role = "assistant", content = list(list(type = "text", text = txt(80)),
        list(type = "tool_use", id = sprintf("toolu_%06d", i), name = "r", input = list(code = paste0("x <- ", txt(30)), timeout = 60L))))
  else if (k == 3) list(role = "user", content = list(list(type = "tool_result", tool_use_id = sprintf("toolu_%06d", i - 1L),
        content = list(list(type = "text", text = txt(400))), is_error = FALSE)))
  else list(role = "assistant", content = list(list(type = "text", text = txt(150))))
}
tj <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)
for (n_msgs in c(60L, 600L)) {
  msgs <- lapply(seq_len(n_msgs), mk_msg)
  head_fields <- list(model = "claude-x", max_tokens = 8192L, stream = TRUE, system = txt(1500))
  cache <- vapply(msgs, function(m) as.character(tj(m)), "")          # serialised ONCE when each message is created
  full <- function() tj(c(head_fields, list(messages = msgs)))
  assembled <- function() paste0(substr(tj(head_fields), 1, nchar(tj(head_fields)) - 1L), ",\"messages\":[", paste(cache, collapse = ","), "]}")
  verbatim <- function() tj(c(head_fields, list(messages = structure(paste0("[", paste(cache, collapse = ","), "]"), class = "json"))))
  cat(sprintf("\nn_msgs=%d  body bytes=%d  assembled identical to full toJSON: %s  json_verbatim identical: %s\n", n_msgs,
              nchar(full(), "bytes"), identical(as.character(full()), assembled()), identical(as.character(full()), as.character(jsonlite::toJSON(c(head_fields, list(messages = structure(paste0("[", paste(cache, collapse = ","), "]"), class = "json"))), auto_unbox = TRUE, null = "null", digits = NA, json_verbatim = TRUE)))))
  show(bench::mark(
    full_toJSON_each_turn   = full(),
    assemble_cached_strings = assembled(),
    json_verbatim_cached    = jsonlite::toJSON(c(head_fields, list(messages = structure(paste0("[", paste(cache, collapse = ","), "]"), class = "json"))), auto_unbox = TRUE, null = "null", digits = NA, json_verbatim = TRUE),
    check = FALSE, min_iterations = 5, max_iterations = 50, filter_gc = FALSE), sprintf("REQUEST BODY per turn, %d messages", n_msgs))
}

## JSONL append: one ~1 KB entry appended to an existing 5 MB session file
f <- file.path(WORK, "append_test.jsonl"); file.copy(file.path(WORK, "session.jsonl"), f, overwrite = TRUE)
entry <- as.character(tj(mk_msg(3L)))
con_open <- file(f, open = "ab")
show(bench::mark(
  cat_append           = cat(entry, "\n", file = f, append = TRUE, sep = ""),
  write_append_writeLines = { con <- file(f, "ab"); writeLines(entry, con, useBytes = TRUE); close(con) },
  kept_open_con_flush  = { writeLines(entry, con_open, useBytes = TRUE); flush(con_open) },
  rewrite_whole_file   = { x <- readLines(f); writeLines(c(x, entry), f, useBytes = TRUE) },
  check = FALSE, min_iterations = 5, max_iterations = 200, filter_gc = FALSE), "APPEND 1 entry to 5 MB JSONL")
close(con_open)
cat("line count sane:", length(readLines(f)) > 3000, "\n")
```

Observed:

```text
versions:  jsonlite 2.0.0, httr2 1.2.2
n_msgs=60  body bytes=114422  assembled identical to full toJSON: TRUE  json_verbatim identical: TRUE
### REQUEST BODY per turn, 60 messages
 full_toJSON_each_turn   12.43ms 18.84ms ... rel 12.00
 assemble_cached_strings  1.43ms  1.85ms ... rel 1.18
 json_verbatim_cached     1.12ms  1.57ms ... rel 1.00
n_msgs=600  body bytes=1026917  assembled identical to full toJSON: TRUE  json_verbatim identical: TRUE
### REQUEST BODY per turn, 600 messages
 full_toJSON_each_turn   160.18ms 171.4ms ... rel 16.60
 assemble_cached_strings   7.17ms  10.4ms ... rel 1.00
 json_verbatim_cached      8.35ms  11ms   ... rel 1.07
### APPEND 1 entry to 5 MB JSONL
 cat_append              56.7µs  68.2µs ... rel 5.54
 write_append_writeLines 39.56µs 56.9µs ... rel 4.62
 kept_open_con_flush      6.27µs 12.3µs ... rel 1.00
 rewrite_whole_file      85.77ms 97.5ms ... rel 7930.00
line count sane: TRUE
```

### 5.4 Streaming accumulation `b2_strings.R` (+ pinpointing `b2c`, fixes `b2d`, scaling `b2e`, JIT test `b2f`)

```r
## Track 19 / Goal 2: incremental string accumulation strategies for streaming LLM output.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
ver("bench")
cat("locale:", Sys.getlocale("LC_CTYPE"), "\n")
set.seed(42)
alphabet <- c(letters, LETTERS, " ", " ", " ", ".", ",", "\n", "é", "中", "ü")
mk_deltas <- function(n) vapply(seq_len(n), function(i) paste(sample(alphabet, sample(1:30, 1), TRUE), collapse = ""), "")
s_paste0_loop <- function(d) { acc <- ""; for (x in d) acc <- paste0(acc, x); acc }
s_c_grow      <- function(d) { buf <- character(); for (x in d) buf <- c(buf, x); paste(buf, collapse = "") }
s_list_prealloc <- function(d) {                      # doubling pre-allocated character buffer
  buf <- character(64L); n <- 0L
  for (x in d) { n <- n + 1L; if (n > length(buf)) length(buf) <- 2L * length(buf); buf[n] <- x }
  paste(buf[seq_len(n)], collapse = "")
}
s_list_append <- function(d) { buf <- list(); n <- 0L; for (x in d) { n <- n + 1L; buf[[n]] <- x }; paste(unlist(buf), collapse = "") }
s_env_buffer <- function(d) {                         # state in an environment, as a callback closure would hold it
  e <- new.env(parent = emptyenv()); e$buf <- character(64L); e$n <- 0L
  push <- function(x) { n <- e$n + 1L; if (n > length(e$buf)) length(e$buf) <- 2L * length(e$buf); e$buf[n] <- x; e$n <- n }
  for (x in d) push(x)
  paste(e$buf[seq_len(e$n)], collapse = "")
}
s_env_list_naive <- function(d) {                    # environment + e$buf[[length+1]] (common naive pattern)
  e <- new.env(parent = emptyenv()); e$buf <- list()
  for (x in d) e$buf[[length(e$buf) + 1L]] <- x
  paste(unlist(e$buf), collapse = "")
}
s_rawcon <- function(d) {
  con <- rawConnection(raw(0), "wb"); on.exit(close(con))
  for (x in d) writeBin(charToRaw(x), con)
  out <- rawToChar(rawConnectionValue(con)); Encoding(out) <- "UTF-8"; out
}
s_textcon <- function(d) {                           # textConnection splits on newlines; must rebuild
  tc_out <- NULL
  con <- textConnection("tc_out", "w", local = TRUE)
  for (x in d) cat(x, file = con)
  close(con)
  paste(tc_out, collapse = "\n")
}
s_file_con <- function(d) {                          # stream to a temp file (crash-safe transcript)
  f <- tempfile(); con <- file(f, "wb"); for (x in d) writeBin(charToRaw(x), con); close(con)
  out <- readChar(f, file.size(f), useBytes = TRUE); Encoding(out) <- "UTF-8"; unlink(f); out
}
for (n in c(500L, 5000L, 50000L)) {
  d <- mk_deltas(n)
  ref <- paste(d, collapse = "")
  cat(sprintf("\nn deltas = %d, total chars = %d, total bytes = %d\n", n, nchar(ref), nchar(ref, "bytes")))
  chk <- c(paste0 = identical(s_paste0_loop(d), ref), c_grow = identical(s_c_grow(d), ref), prealloc = identical(s_list_prealloc(d), ref),
           list_append = identical(s_list_append(d), ref), env = identical(s_env_buffer(d), ref), env_naive = identical(s_env_list_naive(d), ref),
           rawcon = identical(s_rawcon(d), ref), textcon = identical(s_textcon(d), ref), filecon = identical(s_file_con(d), ref))
  print(chk)
  exprs <- list(
    prealloc_chr = quote(s_list_prealloc(d)), list_append = quote(s_list_append(d)), env_buffer = quote(s_env_buffer(d)),
    env_list_naive = quote(s_env_list_naive(d)), c_grow = quote(s_c_grow(d)), rawConnection = quote(s_rawcon(d)),
    textConnection = quote(s_textcon(d)), file_con = quote(s_file_con(d)))
  if (n <= 5000L) exprs$paste0_loop <- quote(s_paste0_loop(d))
  b <- bench::mark(exprs = exprs, check = FALSE, min_iterations = if (n >= 50000L) 3 else 10, max_iterations = 200, filter_gc = FALSE)
  show(b, sprintf("STRING ACCUMULATION: %d deltas", n))
}
d <- mk_deltas(50000L)
cat("\nsystem.time paste0 loop, 50000 deltas:\n"); print(system.time(s_paste0_loop(d)))
d <- mk_deltas(5000L)
running_rebuild_every <- function(d, k) { buf <- character(length(d)); n <- 0L; last <- ""; for (x in d) { n <- n + 1L; buf[n] <- x; if (n %% k == 0L) last <- paste(buf[seq_len(n)], collapse = "") }; last }
show(bench::mark(
  paste0_every_delta = s_paste0_loop(d),
  rebuild_every_1    = running_rebuild_every(d, 1L),
  rebuild_every_50   = running_rebuild_every(d, 50L),
  check = FALSE, min_iterations = 5, filter_gc = FALSE), "RUNNING TEXT (5000 deltas)")
sink_con <- file(nullfile(), "w")
show(bench::mark(
  cat_delta   = for (x in d) cat(x, file = sink_con),
  nothing     = for (x in d) NULL,
  check = FALSE, min_iterations = 5, filter_gc = FALSE), "CONSOLE ECHO of 5000 deltas to nullfile()")
close(sink_con)
```

Observed (`$W/out_b2_strings.txt`):

```text
locale: en_US.UTF-8
n deltas = 500 ... all 9 strategies TRUE
### STRING ACCUMULATION: 500 deltas
 prealloc_chr 211.25µs | list_append 334.29µs | env_buffer 846.26µs (1.34MB) | env_list_naive 394.4µs | c_grow 940.23µs | rawConnection 2.35ms | textConnection 1.76ms | file_con 2.22ms | paste0_loop 4.92ms
n deltas = 5000, total chars = 78301, total bytes = 83397 ... all TRUE
### STRING ACCUMULATION: 5000 deltas
 prealloc_chr 2.37ms (225.67KB) | list_append 3.05ms | env_buffer 39.2ms (142.36MB) | env_list_naive 3.37ms | c_grow 74.55ms (95.65MB) | rawConnection 13.58ms | textConnection 12.75ms | file_con 14.67ms | paste0_loop 425.77ms (199.59MB)
n deltas = 50000, total chars = 775180, total bytes = 825937 ... all TRUE
### STRING ACCUMULATION: 50000 deltas
 prealloc_chr 24.99ms (1.95MB) | list_append 37.84ms | env_buffer 2.94s (13.75GB) | env_list_naive 42.22ms | c_grow 18.45s (9.32GB) | rawConnection 372.4ms | textConnection 1.42s (617.08MB) | file_con 255.5ms
system.time paste0 loop, 50000 deltas:  user 76.557  system 4.233  elapsed 158.999
### RUNNING TEXT (5000 deltas)
 paste0_every_delta 2.24s | rebuild_every_1 13s | rebuild_every_50 95.7ms
### CONSOLE ECHO of 5000 deltas to nullfile()
 cat_delta 20.6ms | nothing 363.3µs
```

`b2c_env_closure.R` (pinpoint) and `b2d_env_fix.R` (fixes), 5,000 appends:

```r
## b2d_env_fix.R
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
set.seed(1); d <- vapply(1:5000, function(i) paste(sample(letters, sample(1:30, 1), TRUE), collapse = ""), "")
A_free_env_complex_assign <- function(d) {
  e <- new.env(parent = emptyenv()); e$buf <- character(64L); e$n <- 0L
  push <- function(x) { n <- e$n + 1L; if (n > length(e$buf)) length(e$buf) <- 2L * length(e$buf); e$buf[n] <- x; e$n <- n }
  for (x in d) push(x); paste(e$buf[seq_len(e$n)], collapse = "") }
F_local_alias <- function(d) {
  e <- new.env(parent = emptyenv()); e$buf <- character(64L); e$n <- 0L
  push <- function(x) { st <- e; n <- st$n + 1L; if (n > length(st$buf)) length(st$buf) <- 2L * length(st$buf); st$buf[n] <- x; st$n <- n }
  for (x in d) push(x); paste(e$buf[seq_len(e$n)], collapse = "") }
G_superassign_closure <- function(d) {
  buf <- character(64L); n <- 0L
  push <- function(x) { n <<- n + 1L; if (n > length(buf)) length(buf) <<- 2L * length(buf); buf[n] <<- x }
  for (x in d) push(x); paste(buf[seq_len(n)], collapse = "") }
H_env_as_argument <- function(d) {
  e <- new.env(parent = emptyenv()); e$buf <- character(64L); e$n <- 0L
  push <- function(x, st) { n <- st$n + 1L; if (n > length(st$buf)) length(st$buf) <- 2L * length(st$buf); st$buf[n] <- x; st$n <- n }
  for (x in d) push(x, e); paste(e$buf[seq_len(e$n)], collapse = "") }
I_chunked_list_of_chunks <- function(d) {            # O(1) amortised, no big vector ever modified: list of 256-slot chunks
  e <- new.env(parent = emptyenv()); e$chunks <- list(); e$cur <- character(256L); e$k <- 0L
  push <- function(x) { st <- e; k <- st$k + 1L; if (k > 256L) { st$chunks[[length(st$chunks) + 1L]] <- st$cur; st$cur <- character(256L); k <- 1L }; st$cur[k] <- x; st$k <- k }
  for (x in d) push(x); paste(c(unlist(e$chunks), e$cur[seq_len(e$k)]), collapse = "") }
fns <- mget(ls(pattern = "^[A-I]_"))
b <- bench::mark(exprs = setNames(lapply(names(fns), function(nm) bquote(.(as.name(nm))(d))), names(fns)), check = TRUE, min_iterations = 3, max_iterations = 30, filter_gc = FALSE)
show(b, "FIXES, 5000 appends")
```

```text
## out_b2c_env_closure.txt (5000 appends; check = TRUE passed)
 A_push_fn_with_length_check        48.45ms  143MB
 B_push_fn_prealloc_no_length_call  62.84ms  191MB
 C_inline_with_length_check          2.54ms  294KB
 D_push_fn_length_check_via_local   52.37ms  142MB
 E_push_fn_list                    144.06ms  142MB
## out_b2d_env_fix.txt
 A_free_env_complex_assign 50.97ms 142.6MB
 F_local_alias             52.59ms 142.4MB
 G_superassign_closure      7.18ms 276.6KB
 H_env_as_argument         56.49ms 142.4MB
 I_chunked_list_of_chunks   7.1ms   10.2MB
## out_b2e_scaling.txt
 n=5000:  G 6.41ms (359.3KB) | I 11.22ms
 n=50000: G 67.7ms (2.69MB)  | I 91.4ms (101.79MB)
## out_b2f_jit_hypothesis.txt (push compiled with compiler::cmpfun vs not): interpreted_push 86.3ms 191MB | cmpfun_push 72.4ms 191MB
```

`b2b_env_buffers.R` (20,000 appends, loops inline in the function owning the environment) showed
no copying for any env variant (8–24 ms, ≤ 3.6 MB), which is what isolates the "called function"
condition.

### 5.5 50 MB file reading `b3_readfile.R` + `b3b_vroom_altrep.R`

```r
## b3_readfile.R (generation + main benchmarks)
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
ver("brio", "vroom", "readr", "stringi", "data.table")
cat("locale:", Sys.getlocale("LC_CTYPE"), "\n")
f <- file.path(WORK, "big50.txt")
if (!file.exists(f) || file.size(f) < 50e6) {
  set.seed(7)
  words <- c("gene", "cluster", "p_val", "0.00123", "avg_log2FC", "Seurat", "read", "write", "error:", "warning", "INFO", "é", "中文", "x <- y + 1", "library(data.table)", "function(x)", "{", "}", "#", "TRUE")
  con <- file(f, "wb")
  total <- 0
  while (total < 50 * 1024^2) {
    lines <- vapply(1:20000, function(i) paste(sample(words, sample(3:14, 1), TRUE), collapse = " "), "")
    txt <- paste0(paste(lines, collapse = "\n"), "\n")
    writeBin(charToRaw(txt), con); total <- total + nchar(txt, "bytes")
  }
  close(con)
}
sz <- file.size(f); cat("file bytes:", sz, "\n")
n_lines <- length(readLines(f)); cat("lines:", n_lines, "\n")
show(bench::mark(
  readLines               = readLines(f),
  readLines_enc_utf8      = readLines(f, encoding = "UTF-8"),
  readLines_con_utf8      = { con <- file(f, encoding = "UTF-8"); on.exit(close(con)); readLines(con) },
  readChar_strsplit       = strsplit(readChar(f, sz, useBytes = TRUE), "\n", fixed = TRUE)[[1]],
  readBin_rawToChar_split = strsplit(rawToChar(readBin(f, "raw", sz)), "\n", fixed = TRUE)[[1]],
  scan_lines              = scan(f, what = "", sep = "\n", quiet = TRUE, quote = "", comment.char = "", blank.lines.skip = FALSE, na.strings = character(), strip.white = FALSE),
  brio_read_lines         = brio::read_lines(f),
  vroom_lines             = vroom::vroom_lines(f, progress = FALSE),
  readr_read_lines        = readr::read_lines(f, progress = FALSE),
  stringi_read_lines      = stringi::stri_read_lines(f),
  fread_lines             = data.table::fread(f, sep = "", header = FALSE, quote = "", strip.white = FALSE, blank.lines.skip = FALSE, na.strings = NULL, showProgress = FALSE)[[1]],
  check = FALSE, min_iterations = 3, max_iterations = 5, filter_gc = FALSE), "READ ALL LINES of 50 MB file")
show(bench::mark(
  readChar_whole          = readChar(f, sz, useBytes = TRUE),
  readBin_rawToChar       = rawToChar(readBin(f, "raw", sz)),
  brio_read_file          = brio::read_file(f),
  readr_read_file         = readr::read_file(f),
  stringi_read_raw        = rawToChar(stringi::stri_read_raw(f)),
  check = FALSE, min_iterations = 3, max_iterations = 10, filter_gc = FALSE), "READ WHOLE FILE AS ONE STRING")
off <- 400000L
show(bench::mark(
  head_readLines_n        = readLines(f, n = 2000L),
  head_vroom_lines        = vroom::vroom_lines(f, n_max = 2000L, progress = FALSE),
  window_readLines_all    = readLines(f)[off + seq_len(2000L)],
  window_con_skip_chunks  = { con <- file(f, "r"); on.exit(close(con)); left <- off; while (left > 0L) { k <- min(left, 50000L); got <- length(readLines(con, n = k)); if (got == 0L) break; left <- left - got }; readLines(con, n = 2000L) },
  window_scan_skip        = scan(f, what = "", sep = "\n", skip = off, nlines = 2000L, quiet = TRUE, quote = "", comment.char = "", blank.lines.skip = FALSE, na.strings = character(), strip.white = FALSE),
  window_vroom_skip       = vroom::vroom_lines(f, skip = off, n_max = 2000L, progress = FALSE),
  window_brio_all         = brio::read_lines(f)[off + seq_len(2000L)],
  check = FALSE, min_iterations = 3, max_iterations = 10, filter_gc = FALSE), "READ TOOL: head(2000) and window at line 400001")
count_nl_chunked <- function(path, chunk = 16L * 1024^2) {
  con <- file(path, "rb"); on.exit(close(con)); n <- 0; last <- as.raw(10)
  repeat { r <- readBin(con, "raw", chunk); if (!length(r)) break; n <- n + sum(r == as.raw(10L)); last <- r[length(r)] }
  n + (last != as.raw(10L))
}
show(bench::mark(
  length_readLines        = length(readLines(f)),
  readBin_chunked_count   = count_nl_chunked(f),
  con_readLines_chunks    = { con <- file(f, "r"); on.exit(close(con)); n <- 0L; repeat { k <- length(readLines(con, n = 100000L)); if (!k) break; n <- n + k }; n },
  vroom_lines_length      = length(vroom::vroom_lines(f, progress = FALSE, altrep = TRUE)),
  fread_nrow              = nrow(data.table::fread(f, sep = "", header = FALSE, quote = "", select = 1L, showProgress = FALSE, blank.lines.skip = FALSE)),
  check = FALSE, min_iterations = 3, max_iterations = 10, filter_gc = FALSE), "COUNT LINES")
cat("counts agree:", count_nl_chunked(f) == n_lines, "\n")
x <- readLines(f, n = 50); y <- readLines(f, n = 50, encoding = "UTF-8"); z <- brio::read_lines(f)[1:50]
cat("Encoding() readLines default:", paste(unique(Encoding(x)), collapse = ","), " encoding='UTF-8':", paste(unique(Encoding(y)), collapse = ","), " brio:", paste(unique(Encoding(z)), collapse = ","), "\n")
```

(`on.exit()` inside `bench::mark` braces produced harmless "closing unused connection" warnings;
`b3b` repeats the key measurements with explicit `close()` and forced materialisation.)

```r
## b3b_vroom_altrep.R
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
f <- file.path(WORK, "big50.txt"); off <- 400000L
force_all <- function(x) { invisible(sum(nchar(x, "bytes"))); x }
show(bench::mark(
  readLines_forced            = force_all(readLines(f)),
  brio_read_lines_forced      = force_all(brio::read_lines(f)),
  vroom_lines_altrep_forced   = force_all(vroom::vroom_lines(f, progress = FALSE)),
  vroom_lines_noaltrep        = force_all(vroom::vroom_lines(f, progress = FALSE, altrep = FALSE)),
  vroom_lines_noaltrep_4thr   = force_all(vroom::vroom_lines(f, progress = FALSE, altrep = FALSE, num_threads = 4)),
  fread_lines_forced          = force_all(data.table::fread(f, sep = "", header = FALSE, quote = "", strip.white = FALSE, blank.lines.skip = FALSE, na.strings = NULL, showProgress = FALSE)[[1]]),
  check = FALSE, min_iterations = 3, max_iterations = 5, filter_gc = FALSE), "READ ALL LINES (materialised)")
show(bench::mark(
  window_vroom_skip_forced    = force_all(vroom::vroom_lines(f, skip = off, n_max = 2000L, progress = FALSE, altrep = FALSE)),
  window_scan_skip            = scan(f, what = "", sep = "\n", skip = off, nlines = 2000L, quiet = TRUE, quote = "", comment.char = "", blank.lines.skip = FALSE, na.strings = character(), strip.white = FALSE),
  window_readLines_skipchunks = { con <- file(f, "r"); left <- off; while (left > 0L) { k <- min(left, 50000L); got <- length(readLines(con, n = k)); if (got == 0L) break; left <- left - got }; r <- readLines(con, n = 2000L); close(con); r },
  window_readBin_newline_scan = { con <- file(f, "rb"); pos <- 0; need <- off; repeat { r <- readBin(con, "raw", 8 * 1024^2); if (!length(r)) break; nl <- which(r == as.raw(10L)); if (length(nl) >= need) { pos <- pos + nl[need]; break }; need <- need - length(nl); pos <- pos + length(r) }; seek(con, pos); r <- readLines(con, n = 2000L); close(con); r },
  check = FALSE, min_iterations = 3, max_iterations = 10, filter_gc = FALSE), "WINDOW at line 400001 (materialised)")
a <- vroom::vroom_lines(f, skip = off, n_max = 2000L, progress = FALSE, altrep = FALSE); b <- readLines(f)[off + seq_len(2000L)]
cat("vroom window identical to readLines window:", identical(a, b), "\n")
```

Observed (`out_b3_readfile.txt`, `out_b3b_vroom_altrep.txt`):

```text
versions:  brio 1.1.5, vroom 1.7.1, readr 2.2.0, stringi 1.8.7, data.table 1.18.2.1
file bytes: 53496779   lines: 900000
### READ ALL LINES of 50 MB file
 readLines 803.9ms | readLines_enc_utf8 1.29s | readLines_con_utf8 1.46s | readChar_strsplit 944.79ms | readBin_rawToChar_split 884.07ms | scan_lines 1.61s | brio_read_lines 545.41ms | vroom_lines 98.95ms (lazy) | readr_read_lines 1.44s | stringi_read_lines 1.66s | fread_lines 671.94ms
### READ WHOLE FILE AS ONE STRING
 readChar_whole 153ms | readBin_rawToChar 169ms | brio_read_file 128ms | readr_read_file 141ms | stringi_read_raw 418ms
### READ TOOL: head(2000) and window at line 400001
 head_readLines_n 1.82ms | head_vroom_lines 1.5ms | window_readLines_all 1.18s | window_con_skip_chunks 545.94ms | window_scan_skip 296.75ms | window_vroom_skip 35.18ms | window_brio_all 584.83ms
### COUNT LINES
 length_readLines 1.21s | readBin_chunked_count 346.1ms | con_readLines_chunks 982.47ms | vroom_lines_length 91.21ms | fread_nrow 501.77ms
counts agree: TRUE
Encoding() readLines default: unknown  encoding='UTF-8': UTF-8,unknown  brio: UTF-8,unknown
### READ ALL LINES (materialised)
 readLines_forced 940.42ms | brio_read_lines_forced 500.29ms | vroom_lines_altrep_forced 519.08ms | vroom_lines_noaltrep 1.19s | vroom_lines_noaltrep_4thr 1.16s | fread_lines_forced 794.37ms
### WINDOW at line 400001 (materialised)
 window_vroom_skip_forced 50.1ms | window_scan_skip 345.2ms | window_readLines_skipchunks 563.4ms | window_readBin_newline_scan 489.2ms
vroom window identical to readLines window: TRUE
readBin-seek window identical: TRUE
```

### 5.6 Regex `b4_regex.R`

```r
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
ver("stringi", "stringr")
cat("locale:", Sys.getlocale("LC_CTYPE"), "\n"); print(pcre_config()); print(extSoftVersion()[c("PCRE", "ICU", "TRE")])
set.seed(3)
tok_ascii <- c("x", "<-", "data.table", "fread(", "library(dplyr)", "function(x)", "{", "}", "if", "else", "for", "i", "in", "seq_len(n)",
               "read_csv(", "write_parquet(", "ERROR", "Error:", "warning", "# comment", "  ", "TRUE", "NULL", "mutate(", "summarise(", "ggplot(", "aes(")
tok_utf8 <- c(tok_ascii, "é", "naïve", "中文", "Ω", "—")
mk <- function(tok, n) vapply(seq_len(n), function(i) paste(sample(tok, sample(4:16, 1), TRUE), collapse = " "), "")
lines_ascii <- mk(tok_ascii, 100000L)
lines_utf8  <- mk(tok_utf8, 100000L)
Encoding(lines_utf8) <- "UTF-8"
cat("non-ASCII share in utf8 set:", mean(!stringi::stri_enc_isascii(lines_utf8)), "\n")
cat("mean bytes/line:", mean(nchar(lines_ascii, "bytes")), "\n")
pats <- list(literal = "data.table", anchored = "^\\s*library\\(", alternate = "\\b(read|write)_[a-z]+\\(", ci_word = "(?i)error")
run <- function(x, label) {
  cat("\n==============", label, "==============\n")
  r_tre   <- grepl(pats$alternate, x)
  r_pcre  <- grepl(pats$alternate, x, perl = TRUE)
  r_icu   <- stringi::stri_detect_regex(x, pats$alternate)
  cat("alternate: TRE==PCRE", identical(r_tre, r_pcre), " PCRE==ICU", identical(r_pcre, r_icu), " matches", sum(r_pcre), "\n")
  cat("literal: fixed==stri_fixed", identical(grepl(pats$literal, x, fixed = TRUE), stringi::stri_detect_fixed(x, pats$literal)), "\n")
  cat("ci: TRE(ignore.case)==PCRE", identical(grepl("error", x, ignore.case = TRUE), grepl(pats$ci_word, x, perl = TRUE)),
      " PCRE==ICU", identical(grepl(pats$ci_word, x, perl = TRUE), stringi::stri_detect_regex(x, pats$ci_word)), "\n")
  show(bench::mark(
    grepl_fixed          = grepl(pats$literal, x, fixed = TRUE),
    grepl_fixed_useBytes = grepl(pats$literal, x, fixed = TRUE, useBytes = TRUE),
    grepl_TRE_escaped    = grepl("data\\.table", x),
    grepl_PCRE_escaped   = grepl("data\\.table", x, perl = TRUE),
    stri_detect_fixed    = stringi::stri_detect_fixed(x, pats$literal),
    stri_detect_regex    = stringi::stri_detect_regex(x, "data\\.table"),
    check = FALSE, min_iterations = 5, max_iterations = 50, filter_gc = FALSE), paste(label, "- LITERAL 'data.table'"))
  show(bench::mark(
    TRE          = grepl(pats$anchored, x),
    TRE_useBytes = grepl(pats$anchored, x, useBytes = TRUE),
    PCRE         = grepl(pats$anchored, x, perl = TRUE),
    PCRE_useBytes= grepl(pats$anchored, x, perl = TRUE, useBytes = TRUE),
    stri_regex   = stringi::stri_detect_regex(x, pats$anchored),
    stringr      = stringr::str_detect(x, pats$anchored),
    check = FALSE, min_iterations = 5, max_iterations = 50, filter_gc = FALSE), paste(label, "- ANCHORED ^\\s*library\\("))
  show(bench::mark(
    TRE          = grepl(pats$alternate, x),
    TRE_useBytes = grepl(pats$alternate, x, useBytes = TRUE),
    PCRE         = grepl(pats$alternate, x, perl = TRUE),
    PCRE_useBytes= grepl(pats$alternate, x, perl = TRUE, useBytes = TRUE),
    stri_regex   = stringi::stri_detect_regex(x, pats$alternate),
    check = FALSE, min_iterations = 5, max_iterations = 50, filter_gc = FALSE), paste(label, "- ALTERNATION \\b(read|write)_[a-z]+\\("))
  show(bench::mark(
    TRE_ignore_case  = grepl("error", x, ignore.case = TRUE),
    PCRE_inline_i    = grepl(pats$ci_word, x, perl = TRUE),
    PCRE_ignore_case = grepl("error", x, perl = TRUE, ignore.case = TRUE),
    fixed_tolower    = grepl("error", tolower(x), fixed = TRUE),
    stri_regex_i     = stringi::stri_detect_regex(x, pats$ci_word),
    stri_fixed_i     = stringi::stri_detect_fixed(x, "error", opts_fixed = stringi::stri_opts_fixed(case_insensitive = TRUE)),
    check = FALSE, min_iterations = 5, max_iterations = 50, filter_gc = FALSE), paste(label, "- CASE-INSENSITIVE 'error'"))
  show(bench::mark(
    regexpr_TRE   = regexpr(pats$alternate, x),
    regexpr_PCRE  = regexpr(pats$alternate, x, perl = TRUE),
    gregexpr_PCRE = gregexpr(pats$alternate, x, perl = TRUE),
    stri_locate_first = stringi::stri_locate_first_regex(x, pats$alternate),
    check = FALSE, min_iterations = 3, max_iterations = 20, filter_gc = FALSE), paste(label, "- MATCH POSITIONS"))
}
run(lines_ascii, "ASCII 100k lines")
run(lines_utf8,  "UTF-8 100k lines (~40% non-ASCII)")
files <- split(lines_utf8, rep(1:2000, each = 50))
show(bench::mark(
  per_file_TRE  = lapply(files, function(l) which(grepl(pats$alternate, l))),
  per_file_PCRE = lapply(files, function(l) which(grepl(pats$alternate, l, perl = TRUE))),
  per_file_stri = lapply(files, function(l) which(stringi::stri_detect_regex(l, pats$alternate))),
  concat_then_split_PCRE = { all <- unlist(files, use.names = FALSE); hit <- grepl(pats$alternate, all, perl = TRUE); split(which(hit), rep(seq_along(files), lengths(files))[hit]) },
  check = FALSE, min_iterations = 3, max_iterations = 20, filter_gc = FALSE), "2000 x 50-line files, pattern per call")
```

Observed (medians; `$W/out_b4_regex.txt`; the label "~40%" is wrong — measured share 0.7792):

```text
UTF-8 Unicode properties TRUE  JIT FALSE ; PCRE "10.44 2024-06-07"  ICU "78.1"  TRE "TRE 0.8.0 R_fixes (BSD)"
non-ASCII share in utf8 set: 0.7792   mean bytes/line: 66.62
ASCII: alternate TRE==PCRE TRUE PCRE==ICU TRUE matches 51564; literal fixed==stri_fixed TRUE; ci TRE==PCRE TRUE PCRE==ICU TRUE
 LITERAL:   grepl_fixed 18.5ms | fixed_useBytes 19ms | TRE_escaped 141.3ms | PCRE_escaped 24.3ms | stri_detect_fixed 13.1ms | stri_detect_regex 50.5ms
 ANCHORED:  TRE 92.28ms | TRE_useBytes 85.92ms | PCRE 9.64ms | PCRE_useBytes 8.88ms | stri_regex 43.04ms | stringr 46.49ms
 ALTERNATE: TRE 2.1s | TRE_useBytes 2.4s | PCRE 74ms | PCRE_useBytes 50.8ms | stri_regex 73.9ms
 CI:        TRE_ignore_case 102.9ms | PCRE_inline_i 35.5ms | PCRE_ignore_case 40.9ms | fixed_tolower 227.4ms | stri_regex_i 68.2ms | stri_fixed_i 38.3ms
 POSITIONS: regexpr_TRE 2.02s | regexpr_PCRE 36.5ms | gregexpr_PCRE 829.59ms (1.54GB) | stri_locate_first 94.14ms
UTF-8 set: alternate matches 46185, all engines agree
 LITERAL:   grepl_fixed 27.6ms | fixed_useBytes 18.3ms | TRE_escaped 212.2ms (27.2MB) | PCRE_escaped 36.1ms | stri_fixed 18ms | stri_regex 73.9ms
 ANCHORED:  TRE 206.8ms | TRE_useBytes 111.1ms | PCRE 28.3ms | PCRE_useBytes 13.7ms | stri_regex 56.9ms | stringr 53.6ms
 ALTERNATE: TRE 1.79s | TRE_useBytes 2.19s | PCRE 58.94ms | PCRE_useBytes 48.51ms | stri_regex 97.53ms
 CI:        TRE 206.1ms | PCRE_inline_i 52.3ms | PCRE_ignore_case 49.9ms | fixed_tolower 256.1ms | stri_regex_i 86.1ms | stri_fixed_i 61.3ms
 POSITIONS: regexpr_TRE 2.01s | regexpr_PCRE 53.69ms | gregexpr_PCRE 938.46ms (1.54GB) | stri_locate_first 84.96ms
### 2000 x 50-line files, pattern per call
 per_file_TRE 1.98s | per_file_PCRE 164.79ms | per_file_stri 120.74ms | concat_then_split_PCRE 56.61ms
```

### 5.7 File discovery `b5_files.R`

```r
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
ver("fs")
root <- file.path(WORK, "tree10k")
if (!dir.exists(root)) {
  set.seed(11)
  dirs <- file.path(root, sprintf("d%02d", 1:20), sprintf("sub%02d", rep(1:10, each = 20)))
  dirs <- unique(dirs); for (d in dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  exts <- c(".R", ".Rmd", ".qmd", ".csv", ".txt", ".json", ".md", ".png")
  paths <- file.path(sample(dirs, 10000, TRUE), paste0("file_", seq_len(10000), sample(exts, 10000, TRUE)))
  for (p in paths) writeBin(as.raw(sample(0:255, sample(10:2000, 1), TRUE)), p)
  dir.create(file.path(root, ".git", "objects"), recursive = TRUE); for (i in 1:500) writeBin(as.raw(1:10), file.path(root, ".git", "objects", sprintf("o%03d", i)))
}
files <- list.files(root, recursive = TRUE, full.names = TRUE)
cat("files (visible):", length(files), " with all.files:", length(list.files(root, recursive = TRUE, all.files = TRUE)), "\n")
show(bench::mark(
  list.files_recursive        = list.files(root, recursive = TRUE, full.names = TRUE),
  list.files_recursive_rel    = list.files(root, recursive = TRUE),
  list.files_pattern_R        = list.files(root, pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
  list.files_all_files        = list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE),
  list.dirs                   = list.dirs(root, recursive = TRUE),
  Sys.glob_2levels            = Sys.glob(file.path(root, "*", "*", "*.R")),
  fs_dir_ls_recurse           = fs::dir_ls(root, recurse = TRUE, type = "file"),
  fs_dir_ls_glob              = fs::dir_ls(root, recurse = TRUE, glob = "*.R"),
  check = FALSE, min_iterations = 5, max_iterations = 30, filter_gc = FALSE), "LIST 10k files")
show(bench::mark(
  file.info_all_cols          = file.info(files),
  file.info_extra_cols_FALSE  = file.info(files, extra_cols = FALSE),
  file.mtime                  = file.mtime(files),
  file.size                   = file.size(files),
  file.exists                 = file.exists(files),
  dir.exists                  = dir.exists(files),
  fs_file_info                = fs::file_info(files),
  fs_dir_info_recurse         = fs::dir_info(root, recurse = TRUE),
  check = FALSE, min_iterations = 5, max_iterations = 30, filter_gc = FALSE), "METADATA of 10k files")
fi <- file.info(files, extra_cols = FALSE)
nm <- basename(files)
show(bench::mark(
  order_mtime_desc      = files[order(fi$mtime, decreasing = TRUE)],
  order_size            = files[order(fi$size)],
  sort_name_locale      = sort(nm),
  sort_name_radix_C     = sort(nm, method = "radix"),
  natural_stringi       = stringi::stri_sort(nm, numeric = TRUE),
  natural_order_stringi = nm[stringi::stri_order(nm, numeric = TRUE)],
  check = FALSE, min_iterations = 10, max_iterations = 200, filter_gc = FALSE), "SORT 10k results")
x <- c("file10.R", "File2.R", "file1.R", "_z.R", "a.R", "B.R", "é.R")
cat("demo  locale sort:", sort(x), "\n  radix sort :", sort(x, method = "radix"), "\n  stringi natural:", stringi::stri_sort(x, numeric = TRUE), "\n")
cat("\nglob2rx('*.R') =", utils::glob2rx("*.R"), "  glob2rx('**/*.qmd') =", utils::glob2rx("**/*.qmd"), "\n")
```

Observed: see §2.4.5 (numbers copied from `$W/out_b5_files.txt`).

### 5.8 base64 `b6_base64.R` (final version, exact 2 MiB input)

```r
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
ver("base64enc", "jsonlite", "openssl", "b64", "secretbase")
f <- file.path(WORK, "img2mb.png")
if (!file.exists(f)) {                                  # a real PNG: noisy raster so it does not compress
  set.seed(5); png(f, width = 1400, height = 1000); par(mar = c(0,0,0,0))
  plot.new(); rasterImage(as.raster(matrix(rgb(runif(1.4e6), runif(1.4e6), runif(1.4e6)), 1000, 1400)), 0, 0, 1, 1); dev.off()
}
raw_img <- readBin(f, "raw", file.size(f))[seq_len(2 * 1024^2)]; cat("image bytes (first 2 MiB of a noisy PNG):", length(raw_img), "\n")
enc <- list(
  base64enc  = base64enc::base64encode(raw_img),
  jsonlite   = jsonlite::base64_enc(raw_img),
  openssl    = openssl::base64_encode(raw_img),
  b64        = b64::encode(raw_img),
  secretbase = secretbase::base64enc(raw_img))
f2 <- tempfile(fileext = ".png"); writeBin(raw_img, f2)
cat("outputs identical to base64enc (no line breaks):\n"); print(vapply(enc, function(e) identical(as.character(e), enc$base64enc), NA))
cat("class of each output:", vapply(enc, function(e) class(e)[1], ""), "\n")
cat("nchar:", nchar(enc$base64enc), " contains newline:", vapply(enc, function(e) grepl("\n", e, fixed = TRUE), NA), "\n")
show(bench::mark(
  base64enc_encode   = base64enc::base64encode(raw_img),
  jsonlite_base64_enc= jsonlite::base64_enc(raw_img),
  openssl_encode     = openssl::base64_encode(raw_img),
  b64_encode         = b64::encode(raw_img),
  secretbase_enc     = secretbase::base64enc(raw_img),
  base64enc_from_file= base64enc::base64encode(f2),
  check = FALSE, min_iterations = 10, max_iterations = 100, filter_gc = FALSE), "BASE64 ENCODE 2 MB")
s <- enc$base64enc
show(bench::mark(
  base64enc_decode   = base64enc::base64decode(s),
  jsonlite_base64_dec= jsonlite::base64_dec(s),
  openssl_decode     = openssl::base64_decode(s),
  b64_decode         = b64::decode(s)[[1]],
  secretbase_dec     = secretbase::base64dec(s, convert = FALSE),
  check = FALSE, min_iterations = 10, max_iterations = 100, filter_gc = FALSE), "BASE64 DECODE 2 MB")
cat("decode round-trips:", identical(base64enc::base64decode(s), raw_img), identical(jsonlite::base64_dec(s), raw_img),
    identical(openssl::base64_decode(s), raw_img), identical(secretbase::base64dec(s, convert = FALSE), raw_img), "\n")
body <- list(model = "m", messages = list(list(role = "user", content = list(
  list(type = "image", source = list(type = "base64", media_type = "image/png", data = s)),
  list(type = "text", text = "Describe this plot")))))
show(bench::mark(
  jsonlite_toJSON_with_image = jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"),
  yyjsonr_with_image         = yyjsonr::write_json_str(body, opts = yyjsonr::opts_write_json(auto_unbox = TRUE)),
  splice_verbatim            = { b <- body; b$messages[[1]]$content[[1]]$source$data <- "@@IMG@@"; sub("\"@@IMG@@\"", paste0("\"", s, "\""), jsonlite::toJSON(b, auto_unbox = TRUE, null = "null"), fixed = TRUE) },
  jsonlite_json_verbatim     = { b <- body; b$messages[[1]]$content[[1]]$source$data <- structure(paste0("\"", s, "\""), class = "json"); jsonlite::toJSON(b, auto_unbox = TRUE, null = "null", json_verbatim = TRUE) },
  check = FALSE, min_iterations = 5, max_iterations = 30, filter_gc = FALSE), "JSON body containing a 2.7 MB base64 image")
a <- as.character(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"))
b <- body; b$messages[[1]]$content[[1]]$source$data <- structure(paste0("\"", s, "\""), class = "json")
c2 <- as.character(jsonlite::toJSON(b, auto_unbox = TRUE, null = "null", json_verbatim = TRUE))
cat("json_verbatim output identical:", identical(a, c2), "\n")
show(bench::mark(
  paste0_data_uri = paste0("data:image/png;base64,", s),
  base64enc_dataURI = base64enc::dataURI(raw_img, mime = "image/png"),
  check = FALSE, min_iterations = 10, filter_gc = FALSE), "data: URI")
```

```text
versions:  base64enc 0.1.6, jsonlite 2.0.0, openssl 2.3.5, b64 0.1.7, secretbase 1.2.0
image bytes (first 2 MiB of a noisy PNG): 2097152
outputs identical to base64enc (no line breaks): base64enc TRUE jsonlite FALSE openssl TRUE b64 TRUE secretbase TRUE
nchar: 2796204  contains newline: FALSE TRUE FALSE FALSE FALSE
### BASE64 ENCODE 2 MB
 base64enc_encode 9.71ms | jsonlite_base64_enc 9.83ms | openssl_encode 12.17ms | b64_encode 8.9ms | secretbase_enc 24.56ms | base64enc_from_file 31.78ms
### BASE64 DECODE 2 MB
 base64enc_decode 29.63ms | jsonlite_base64_dec 42.58ms | openssl_decode 248.47ms | b64_decode 3.73ms | secretbase_dec 167.12ms
decode round-trips: TRUE TRUE TRUE TRUE
### JSON body containing a 2.7 MB base64 image
 jsonlite_toJSON_with_image 68.1ms | yyjsonr_with_image 10.2ms | splice_verbatim 20ms | jsonlite_json_verbatim 113.6ms
json_verbatim output identical: TRUE
### data: URI
 paste0_data_uri 7.82ms | base64enc_dataURI 19.12ms
## separately: jsonlite::base64_enc(as.raw(1:200)) -> first "\n" at position 73
```

### 5.9 Hashing `b7_hash.R`

```r
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
ver("digest", "rlang", "openssl", "secretbase", "xxhashlite")
cat("tools::sha256sum exists in this R:", exists("sha256sum", envir = asNamespace("tools")), "\n")
cat("formals(tools::md5sum):", paste(names(formals(tools::md5sum)), collapse = ", "), "\n")
set.seed(9)
s1k  <- paste(sample(c(letters, " "), 1000, TRUE), collapse = "")
s1m  <- paste(rep(s1k, 1000), collapse = "")
f5m  <- file.path(WORK, "session.jsonl"); cat("file bytes:", file.size(f5m), "\n")
df   <- data.frame(a = runif(1e5), b = sample(letters, 1e5, TRUE), c = seq_len(1e5))
lines1k <- vapply(1:1000, function(i) paste(sample(letters, 40, TRUE), collapse = ""), "")
show(bench::mark(
  digest_md5 = digest::digest(s1k, algo = "md5", serialize = FALSE), digest_sha256 = digest::digest(s1k, algo = "sha256", serialize = FALSE),
  digest_xxhash64 = digest::digest(s1k, algo = "xxhash64", serialize = FALSE), rlang_hash = rlang::hash(s1k),
  openssl_md5 = openssl::md5(s1k), openssl_sha256 = openssl::sha256(s1k), secretbase_sha256 = secretbase::sha256(s1k, convert = TRUE),
  secretbase_siphash = secretbase::siphash13(s1k), xxhashlite_xxh128 = xxhashlite::xxhash(s1k, algo = "xxh128", as_raw = FALSE),
  check = FALSE, min_iterations = 1000, max_iterations = 20000, filter_gc = FALSE), "HASH 1 KB string")
show(bench::mark(
  digest_md5 = digest::digest(s1m, algo = "md5", serialize = FALSE), digest_sha256 = digest::digest(s1m, algo = "sha256", serialize = FALSE),
  digest_xxhash64 = digest::digest(s1m, algo = "xxhash64", serialize = FALSE), rlang_hash = rlang::hash(s1m),
  openssl_md5 = openssl::md5(s1m), openssl_sha256 = openssl::sha256(s1m), secretbase_sha256 = secretbase::sha256(s1m, convert = TRUE),
  xxhashlite_xxh128 = xxhashlite::xxhash(s1m, algo = "xxh128", as_raw = FALSE),
  check = FALSE, min_iterations = 20, max_iterations = 500, filter_gc = FALSE), "HASH 1 MB string")
show(bench::mark(
  tools_md5sum = tools::md5sum(f5m), digest_md5_file = digest::digest(f5m, algo = "md5", file = TRUE),
  digest_xxh64_file = digest::digest(f5m, algo = "xxhash64", file = TRUE), rlang_hash_file = rlang::hash_file(f5m),
  openssl_md5_con = openssl::md5(file(f5m)), openssl_sha256_con = openssl::sha256(file(f5m)),
  secretbase_sha256_file = secretbase::sha256(file = f5m), readBin_then_rlang = rlang::hash(readBin(f5m, "raw", file.size(f5m))),
  check = FALSE, min_iterations = 10, max_iterations = 100, filter_gc = FALSE), "HASH 5 MB file")
show(bench::mark(
  digest_md5_serialize = digest::digest(df, algo = "md5"), digest_xxh64_ser = digest::digest(df, algo = "xxhash64"),
  rlang_hash_object = rlang::hash(df), secretbase_sha256_obj = secretbase::sha256(df),
  xxhashlite_obj = xxhashlite::xxhash(df, algo = "xxh128", as_raw = FALSE), serialize_then_openssl = openssl::md5(serialize(df, NULL)),
  check = FALSE, min_iterations = 10, max_iterations = 200, filter_gc = FALSE), "HASH R object (data.frame 1e5 x 3, ~2 MB)")
show(bench::mark(
  openssl_md5_vectorised = openssl::md5(lines1k),
  vapply_digest_md5      = vapply(lines1k, digest::digest, "", algo = "md5", serialize = FALSE, USE.NAMES = FALSE),
  vapply_rlang_hash      = vapply(lines1k, rlang::hash, "", USE.NAMES = FALSE),
  digest_getVDigest      = { vd <- digest::getVDigest("md5"); vd(lines1k, serialize = FALSE) },
  check = FALSE, min_iterations = 10, max_iterations = 200, filter_gc = FALSE), "HASH 1000 short strings")
tf <- tempfile(); writeBin(charToRaw(s1k), tf)
cat("md5 agree (tools file / digest / openssl):", unname(tools::md5sum(tf)), digest::digest(s1k, "md5", serialize = FALSE), as.character(openssl::md5(s1k)), "\n")
cat("rlang::hash is serialization-based (object): rlang::hash('a') =", rlang::hash("a"), "; rlang::hash_file of 'a' file:", { tf2 <- tempfile(); writeBin(charToRaw("a"), tf2); rlang::hash_file(tf2) }, "\n")
cat("rlang::hash(s) differs across encodings? ", rlang::hash(enc2utf8("é")) == rlang::hash(iconv("é", "UTF-8", "latin1")), "\n")
```

```text
versions:  digest 0.6.39, rlang 1.1.7, openssl 2.3.5, secretbase 1.2.0, xxhashlite 0.2.2
tools::sha256sum exists in this R: FALSE
formals(tools::md5sum): files
file bytes: 5534095
(timings as in §2.4.7)
md5 agree (tools file / digest / openssl): 5f63057ba7af0a9b08373167305a5018 5f63057ba7af0a9b08373167305a5018 5f63057ba7af0a9b08373167305a5018
rlang::hash is serialization-based (object): rlang::hash('a') = 4d52a7da68952b85f039e85a90f9bbd2 ; rlang::hash_file of 'a' file: a96faf705af16834e6c632b61e964e1f
rlang::hash(s) differs across encodings?  FALSE      # i.e. the two hashes are NOT equal
```

### 5.10 Capability detection cost `b8_capdetect.R`

```r
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
.libPaths(setdiff(.libPaths(), PRIV))  # measure the USER's real library only (system lib)
cat(".libPaths():", .libPaths(), "\n")
cat("installed packages in library:", length(list.dirs(.libPaths()[1], recursive = FALSE)), "\n")
gptr_perf_packages <- c(
  "data.table", "vroom", "arrow", "readr", "nanoparquet", "duckdb", "duckplyr", "collapse", "dplyr", "dtplyr", "tidytable",
  "matrixStats", "stringi", "stringr", "stringfish", "qs2", "fst", "kit", "Matrix", "bigmemory", "DelayedArray", "HDF5Array",
  "BPCells", "mirai", "future", "future.apply", "furrr", "crew", "BiocParallel", "targets", "bench", "profvis",
  "ggplot2", "scattermore", "ggrastr", "Seurat", "SeuratObject", "SingleCellExperiment", "polars", "RcppParallel")
detect_A <- function(pkgs) {
  paths <- find.package(pkgs, quiet = TRUE)
  names(paths) <- basename(paths)
  vapply(pkgs, function(p) {
    path <- paths[p]
    if (is.na(path)) return(NA_character_)
    d <- tryCatch(readRDS(file.path(path, "Meta", "package.rds"))$DESCRIPTION, error = function(e) NULL)
    if (is.null(d)) NA_character_ else unname(d[["Version"]])
  }, "")
}
detect_B <- function(pkgs) vapply(pkgs, function(p) if (nzchar(system.file(package = p))) utils::packageDescription(p, fields = "Version") else NA_character_, "")
detect_C <- function(pkgs) { ip <- utils::installed.packages(fields = "Version", noCache = TRUE); unname(ip[match(pkgs, rownames(ip)), "Version"]) }
detect_D <- function(pkgs) vapply(pkgs, function(p) tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_), "")
a <- detect_A(gptr_perf_packages); b <- detect_B(gptr_perf_packages); c3 <- detect_C(gptr_perf_packages); d <- detect_D(gptr_perf_packages)
cat("A==B:", identical(unname(a), unname(b)), " A==C:", identical(unname(a), c3), " A==D:", identical(unname(a), unname(d)), "\n"); print(data.frame(pkg = names(a), A = unname(a), C = c3, D = unname(d))[!(unname(a) %in% c3 & unname(a) %in% unname(d)) | is.na(a), ], row.names = FALSE)
show(bench::mark(
  A_find.package_Meta_rds   = detect_A(gptr_perf_packages),
  B_system.file_pkgDesc     = detect_B(gptr_perf_packages),
  C_installed.packages      = detect_C(gptr_perf_packages),
  D_packageVersion_tryCatch = detect_D(gptr_perf_packages),
  check = FALSE, memory = FALSE, min_iterations = 3, max_iterations = 20, filter_gc = FALSE), sprintf("DETECT %d packages without loading", length(gptr_perf_packages)))
cat("loaded now:", paste(intersect(gptr_perf_packages, loadedNamespaces()), collapse = ", "), "\n")
present <- names(a)[!is.na(a)]
load_cost <- vapply(present, function(p) {
  out <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", "-e",
         shQuote(sprintf("t <- system.time(ok <- suppressPackageStartupMessages(requireNamespace('%s', quietly = TRUE)))[['elapsed']]; cat(ok, t, length(loadedNamespaces()))", p))),
         stdout = TRUE, stderr = FALSE)
  paste(out, collapse = " ")
}, "")
lc <- do.call(rbind, strsplit(load_cost, " "))
res <- data.frame(pkg = present, version = unname(a[present]), ok = lc[, 1], load_sec = as.numeric(lc[, 2]), n_namespaces_after = as.integer(lc[, 3]))
res <- res[order(-res$load_sec), ]
print(res, row.names = FALSE)
cat("TOTAL seconds if a harness called requireNamespace() on all", nrow(res), "present packages (sum of fresh-process loads):", sum(res$load_sec), "\n")
```

```text
.libPaths(): /Library/Frameworks/R.framework/Versions/4.4-arm64/Resources/library
installed packages in library: 615
A==B: TRUE  A==C: FALSE  A==D: FALSE
 (differences: C lacks bench (loaded from the removed private lib); D normalises Matrix 1.7-5 -> 1.7.5, RcppParallel 5.1.11-2 -> 5.1.11.2)
### DETECT 40 packages without loading
 A_find.package_Meta_rds 19.8ms | B_system.file_pkgDesc 21.9ms | C_installed.packages 218.8ms | D_packageVersion_tryCatch 16.5ms
(load table as in §2.5)
TOTAL seconds if a harness called requireNamespace() on all 27 present packages (sum of fresh-process loads): 36.39
```

Crash reproduction (executed, fresh processes, private lib on `.libPaths()`):

```sh
for nxt in duckdb qs2 collapse data.table secretbase jsonlite; do
  Rscript --vanilla -e ".libPaths(c(.libPaths(), '$PRIV')); r <- try(loadNamespace('BPCells'), silent=TRUE); x <- loadNamespace('$nxt'); cat('$nxt OK\n')"
done
# every run:  *** caught segfault ***  address 0x202c29656c696620, cause 'invalid permissions'
# control:    Rscript --vanilla -e "x <- loadNamespace('mirai')"  -> mirai OK (also after loading HDF5Array, duckdb or arrow first)
```

### 5.11 Goal 1 evidence scripts (`b9_io.R`, `b10_wrangle.R`, `b10b`, `b10c`, `b12_parallel.R`, `b18`)

```r
## b9_io.R
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
ver("data.table", "vroom", "readr", "arrow", "duckdb", "nanoparquet", "qs2", "qs", "fst")
cat("data.table threads:", data.table::getDTthreads(), "  arrow cpu_count:", arrow::cpu_count(), "\n")
set.seed(1)
n <- 1e6
df <- data.frame(id = seq_len(n), grp = sample(sprintf("g%03d", 1:500), n, TRUE), x = rnorm(n), y = runif(n),
                 k = sample(1:1000, n, TRUE), flag = sample(c(TRUE, FALSE), n, TRUE),
                 txt = sample(c("alpha", "beta", "gamma delta", "epsilon, zeta", "é中"), n, TRUE),
                 day = as.Date("2020-01-01") + sample(0:2000, n, TRUE), stringsAsFactors = FALSE)
cat("object.size(df):", format(object.size(df), units = "MB"), "\n")
d <- file.path(WORK, "io"); dir.create(d, showWarnings = FALSE)
csv <- file.path(d, "df.csv")
data.table::fwrite(df, csv); cat("csv bytes:", file.size(csv), "\n")
show(bench::mark(
  base_write.csv       = write.csv(df, file.path(d, "w_base.csv"), row.names = FALSE),
  data.table_fwrite    = data.table::fwrite(df, file.path(d, "w_dt.csv")),
  vroom_write          = vroom::vroom_write(df, file.path(d, "w_vroom.csv"), delim = ",", progress = FALSE),
  readr_write_csv      = readr::write_csv(df, file.path(d, "w_readr.csv"), progress = FALSE),
  arrow_write_csv      = arrow::write_csv_arrow(df, file.path(d, "w_arrow.csv")),
  check = FALSE, min_iterations = 2, max_iterations = 3, filter_gc = FALSE, memory = FALSE), "WRITE CSV 1e6 x 8")
con <- DBI::dbConnect(duckdb::duckdb())
show(bench::mark(
  base_read.csv        = read.csv(csv),
  data.table_fread     = data.table::fread(csv, showProgress = FALSE),
  vroom_altrep_forced  = { x <- vroom::vroom(csv, progress = FALSE, show_col_types = FALSE); invisible(lapply(x, function(col) col[length(col)])); sum(nchar(x$txt)) },
  vroom_no_altrep      = vroom::vroom(csv, progress = FALSE, show_col_types = FALSE, altrep = FALSE),
  readr_read_csv       = readr::read_csv(csv, progress = FALSE, show_col_types = FALSE, lazy = FALSE),
  arrow_read_csv       = arrow::read_csv_arrow(csv),
  duckdb_read_csv      = DBI::dbGetQuery(con, sprintf("SELECT * FROM read_csv_auto('%s')", csv)),
  check = FALSE, min_iterations = 2, max_iterations = 3, filter_gc = FALSE, memory = FALSE), "READ CSV 1e6 x 8 (~60 MB)")
pq <- file.path(d, "df.parquet")
show(bench::mark(
  arrow_write_parquet       = arrow::write_parquet(df, pq),
  nanoparquet_write_parquet = nanoparquet::write_parquet(df, file.path(d, "np.parquet")),
  duckdb_copy_parquet       = { duckdb::duckdb_register(con, "df_view", df); DBI::dbExecute(con, sprintf("COPY df_view TO '%s' (FORMAT parquet)", file.path(d, "dd.parquet"))); duckdb::duckdb_unregister(con, "df_view") },
  check = FALSE, min_iterations = 2, max_iterations = 3, filter_gc = FALSE, memory = FALSE), "WRITE PARQUET")
cat("parquet bytes: arrow", file.size(pq), " nanoparquet", file.size(file.path(d, "np.parquet")), " duckdb", file.size(file.path(d, "dd.parquet")), "\n")
show(bench::mark(
  arrow_read_parquet        = as.data.frame(arrow::read_parquet(pq)),
  nanoparquet_read_parquet  = nanoparquet::read_parquet(pq),
  duckdb_read_parquet       = DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", pq)),
  arrow_dataset_filter_agg  = dplyr::collect(dplyr::summarise(dplyr::group_by(dplyr::filter(arrow::open_dataset(pq), k > 500L), grp), m = mean(x))),
  duckdb_filter_agg         = DBI::dbGetQuery(con, sprintf("SELECT grp, avg(x) AS m FROM read_parquet('%s') WHERE k > 500 GROUP BY grp", pq)),
  check = FALSE, min_iterations = 3, max_iterations = 5, filter_gc = FALSE, memory = FALSE), "READ PARQUET / query without full load")
DBI::dbDisconnect(con, shutdown = TRUE)
lst <- list(df = df, model = lm(x ~ y + k, data = df[1:1e5, ]), meta = list(a = 1:10, b = letters))
f <- function(ext) file.path(d, paste0("obj.", ext))
show(bench::mark(
  saveRDS_default_gzip  = saveRDS(df, f("rds")),
  saveRDS_uncompressed  = saveRDS(df, f("u.rds"), compress = FALSE),
  saveRDS_xz            = saveRDS(df, f("xz.rds"), compress = "xz"),
  qs2_qs_save           = qs2::qs_save(df, f("qs2")),
  qs2_qs_save_4thr      = qs2::qs_save(df, f("4.qs2"), nthreads = 4),
  qs2_qd_save           = qs2::qd_save(df, f("qdata")),
  qs_qsave_legacy       = qs::qsave(df, f("qs")),
  fst_write             = fst::write_fst(df, f("fst")),
  check = FALSE, min_iterations = 2, max_iterations = 3, filter_gc = FALSE, memory = FALSE), "SAVE data.frame 1e6 x 8")
sizes <- vapply(c("rds", "u.rds", "xz.rds", "qs2", "4.qs2", "qdata", "qs", "fst"), function(e) file.size(f(e)), 0)
print(round(sizes / 1e6, 1))
show(bench::mark(
  readRDS_gzip          = readRDS(f("rds")),
  readRDS_uncompressed  = readRDS(f("u.rds")),
  qs2_qs_read           = qs2::qs_read(f("qs2")),
  qs2_qs_read_4thr      = qs2::qs_read(f("4.qs2"), nthreads = 4),
  qs2_qd_read           = qs2::qd_read(f("qdata")),
  qs_qread_legacy       = qs::qread(f("qs")),
  fst_read              = fst::read_fst(f("fst")),
  check = FALSE, min_iterations = 3, max_iterations = 5, filter_gc = FALSE, memory = FALSE), "READ data.frame 1e6 x 8")
cat("round-trip identical: rds", identical(readRDS(f("rds")), df), " qs2", identical(qs2::qs_read(f("qs2")), df), " qdata", identical(qs2::qd_read(f("qdata")), df),
    " fst", identical(fst::read_fst(f("fst")), df), "\n")
r1 <- tryCatch({ qs2::qs_save(lst, f("lst.qs2")); inherits(qs2::qs_read(f("lst.qs2"))$model, "lm") }, error = function(e) conditionMessage(e))
r2 <- tryCatch({ qs2::qd_save(lst, f("lst.qdata")); x <- qs2::qd_read(f("lst.qdata")); class(x$model) }, error = function(e) paste("ERROR:", conditionMessage(e)), warning = function(w) paste("WARNING:", conditionMessage(w)))
cat("qs_save(list with lm) ok:", r1, "\nqd_save(list with lm):", paste(r2, collapse = " "), "\n")
qs2::qs_to_rds(f("qs2"), f("conv.rds")); cat("qs_to_rds then readRDS identical:", identical(readRDS(f("conv.rds")), df), "\n")
```

```text
versions:  data.table 1.18.2.1, vroom 1.7.1, readr 2.2.0, arrow 23.0.1.1, duckdb 1.5.0, nanoparquet 0.4.3, qs2 0.1.7, qs 0.27.3, fst 0.9.8
data.table threads: 4   arrow cpu_count: 8
object.size(df): 49.6 Mb      csv bytes: 77439312
(tables as in §2.3)
parquet bytes: arrow 24301262  nanoparquet 23154944  duckdb 23358128
   rds  u.rds xz.rds    qs2  4.qs2  qdata     qs    fst
  19.9   59.6   16.9   19.1   19.1   18.3   16.9   34.5
round-trip identical: rds TRUE  qs2 TRUE  qdata TRUE  fst TRUE
qs_save(list with lm) ok: TRUE
qd_save(list with lm): WARNING: Objects of type language are not supported in qdata format
qs_to_rds then readRDS identical: TRUE
```

```r
## b10b_collapse_qualified.R
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
suppressPackageStartupMessages(library(collapse))
ver("collapse")
set.seed(2); n <- 1e6
df <- data.frame(g = sample(1e4, n, TRUE), g2 = sample(letters, n, TRUE), x = rnorm(n), y = runif(n))
show(bench::mark(
  qualified_names   = collapse::fsummarise(collapse::fgroup_by(df, g2, g), sx = collapse::fsum(x), my = collapse::fmean(y), n = collapse::fnobs(x)),
  unqualified_names = fsummarise(fgroup_by(df, g2, g), sx = fsum(x), my = fmean(y), n = fnobs(x)),
  vector_api        = { gg <- GRP(df, ~ g2 + g); data.frame(gg$groups, sx = fsum(df$x, gg, use.g.names = FALSE), my = fmean(df$y, gg, use.g.names = FALSE), n = fnobs(df$x, gg, use.g.names = FALSE)) },
  data.table        = data.table::as.data.table(df)[, .(sx = sum(x), my = mean(y), n = .N), by = .(g2, g)],
  check = FALSE, min_iterations = 3, max_iterations = 5, filter_gc = FALSE, memory = FALSE), "collapse qualified vs unqualified, 1e6 rows, 260k groups")
a <- collapse::fsummarise(collapse::fgroup_by(df, g2, g), sx = collapse::fsum(x)); b <- fsummarise(fgroup_by(df, g2, g), sx = fsum(x))
cat("same result:", isTRUE(all.equal(as.data.frame(a), as.data.frame(b))), " groups:", nrow(b), "\n")
```

```text
versions:  collapse 2.1.6
 qualified_names 4.68s (151 GCs) | unqualified_names 49.26ms | vector_api 45.63ms | data.table 178.61ms
same result: TRUE  groups: 254467
```

```r
## b10c_dt_gforce.R  (run with DT_THREADS=4 and DT_THREADS=1)
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")
suppressPackageStartupMessages(library(data.table)); ver("data.table"); THR <- as.integer(Sys.getenv("DT_THREADS", "4")); setDTthreads(THR); cat("DT threads:", getDTthreads(), "\n")
set.seed(2); n <- 1e6
dt <- data.table(g = sample(1e4, n, TRUE), g2 = sample(letters, n, TRUE), x = rnorm(n))
show(bench::mark(
  unqualified_mean   = dt[, .(m = mean(x)), by = .(g2, g)],
  qualified_mean     = dt[, .(m = base::mean(x)), by = .(g2, g)],
  unqualified_median = dt[, .(m = median(x)), by = .(g2, g)],
  qualified_median   = dt[, .(m = stats::median(x)), by = .(g2, g)],
  check = FALSE, min_iterations = 3, max_iterations = 5, filter_gc = FALSE, memory = FALSE), "data.table GForce with qualified names (260k groups)")
options(datatable.verbose = TRUE)
out <- capture.output(invisible(dt[, .(m = base::mean(x)), by = .(g2, g)])); cat(grep("GForce|lapply optimization|Making each group", out, value = TRUE), sep = "\n")
out <- capture.output(invisible(dt[, .(m = mean(x)), by = .(g2, g)])); cat(grep("GForce|lapply optimization|Making each group", out, value = TRUE), sep = "\n")
```

```text
4 threads: unqualified_mean 1.16s | qualified_mean 881.58ms | unqualified_median 245.13ms | qualified_median 8.78s
1 thread:  unqualified_mean 315.75ms | qualified_mean 828ms | unqualified_median 269.63ms | qualified_median 9.73s
lapply optimization is on, j unchanged as 'list(base::mean(x))'
GForce is on, but not activated for this query; left j unchanged (see ?GForce)
Making each group and running j (GForce FALSE) ...
lapply optimization is on, j unchanged as 'list(mean(x))'
GForce optimized j to 'list(gmean(x))' (see ?GForce)
Making each group and running j (GForce TRUE) ... gforce initial population of grp took 0.006
```

(The 4-thread GForce mean being slower than 1 thread is attributed to OpenMP oversubscription at load
average ~50–70; UNCERTAIN.)

`b10_wrangle.R` (grouped/sort/top-n/matrix code) is in `$W`; its full output is summarised in §2.3.
`b12_parallel.R` (final version, `Sys.setenv(R_LIBS = PRIV)` added after the hang) and its output are in
`$W/b12_parallel.R` and `$W/out_b12_parallel.txt`; numbers in §2.3.

```r
## b18_duckplyr_smoke.R
.libPaths(c(.libPaths(), "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"))
Sys.setenv(DUCKPLYR_FALLBACK_COLLECT = "0")
suppressPackageStartupMessages(library(dplyr))
pq <- file.path("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/io", "df.parquet")
x <- duckplyr::read_parquet_duckdb(pq)
t <- system.time(res <- x |> filter(k > 500L) |> summarise(m = mean(x), n = n(), .by = grp) |> arrange(grp) |> collect())[["elapsed"]]
r <- tryCatch({ nrow(x); "materialised" }, error = function(e) paste("ERROR:", conditionMessage(e)))
```

```text
duckplyr 1.2.1  duckdb 1.5.0
class: prudent_duckplyr_df duckplyr_df
rows: 500  elapsed: 0.087 s
nrow() on lazy frame with default prudence: ERROR: Materialization would result in more than 125000 rows. Use `collect()` or `as_tibble()` to materialize.
```

### 5.12 Capability detection prototype `proto_caps.R` (complete)

```r
gptr_perf_registry <- function() {
  r <- utils::read.table(header = TRUE, stringsAsFactors = FALSE, sep = "|", strip.white = TRUE, text = "
pkg                 | cat       | repo  | role
data.table          | io+wrangle| CRAN  | fread/fwrite, fast grouped ops, in-place :=
vroom               | io        | CRAN  | lazy fast delimited reader
arrow               | io+disk   | CRAN  | CSV/Parquet/Feather, open_dataset
readr               | io        | CRAN  | tidyverse CSV reader
nanoparquet         | io        | CRAN  | dependency-free Parquet
duckdb              | disk      | CRAN  | SQL on files, larger than memory
duckplyr            | disk      | CRAN  | dplyr on duckdb
collapse            | wrangle   | CRAN  | fast grouped stats
dplyr               | wrangle   | CRAN  | tidy verbs
dtplyr              | wrangle   | CRAN  | dplyr to data.table
tidytable           | wrangle   | CRAN  | tidy verbs on data.table
matrixStats         | stats     | CRAN  | row/col stats
kit                 | stats     | CRAN  | topn, parallel pmin/psum
stringi             | strings   | CRAN  | ICU strings, natural sort
stringr             | strings   | CRAN  | tidy strings on stringi
qs2                 | serialize | CRAN  | fast object files
fst                 | serialize | CRAN  | fast data.frame files
Matrix              | matrix    | CRAN  | sparse matrices
bigmemory           | matrix    | CRAN  | file-backed matrices
DelayedArray        | matrix    | Bioc  | block-processed arrays
HDF5Array           | matrix    | Bioc  | on-disk HDF5 arrays
BPCells             | matrix    | GitHub| on-disk single-cell matrices
mirai               | parallel  | CRAN  | async workers
future              | parallel  | CRAN  | futures API
future.apply        | parallel  | CRAN  | future_lapply
crew                | parallel  | CRAN  | worker controllers (targets)
BiocParallel        | parallel  | Bioc  | Bioc parallel back-ends
targets             | pipeline  | CRAN  | cached pipelines
bench               | profile   | CRAN  | benchmarking
profvis             | profile   | CRAN  | profiling
ggplot2             | plot      | CRAN  | grammar of graphics
scattermore         | plot      | CRAN  | rasterised scatter
ggrastr             | plot      | CRAN  | rasterise ggplot layers
Seurat              | sc        | CRAN  | single-cell analysis
SeuratObject        | sc        | CRAN  | Seurat v5 layers
SingleCellExperiment| sc        | Bioc  | Bioc single-cell container
")
  r
}

## Fast, side-effect free: find.package() + Meta/package.rds (never loads a namespace).
.gptr_pkg_meta <- function(pkgs) {
  paths <- find.package(pkgs, quiet = TRUE)
  names(paths) <- basename(paths)
  out <- lapply(pkgs, function(p) {
    path <- unname(paths[p])
    if (is.na(path)) return(c(version = NA_character_, compiled = NA_character_, built = NA_character_, path = NA_character_))
    d <- tryCatch(readRDS(file.path(path, "Meta", "package.rds"))$DESCRIPTION, error = function(e) NULL)
    if (is.null(d)) return(c(version = NA_character_, compiled = NA_character_, built = NA_character_, path = path))
    c(version = unname(d["Version"]), compiled = unname(d["NeedsCompilation"]),
      built = unname(sub(";.*$", "", d["Built"])), path = path)
  })
  m <- do.call(rbind, out)
  data.frame(pkg = pkgs, m, row.names = NULL, stringsAsFactors = FALSE)
}

## Optional: probe that compiled packages actually load, each in its OWN child process
## (R < 4.6.1: one failed dyn.load() with a long dlerror() message corrupts the process, PR#19029).
.gptr_probe_loadable <- function(pkgs, max_parallel = 2L, timeout = 60) {
  if (!length(pkgs)) return(data.frame(pkg = character(), loadable = logical(), error = character()))
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  env <- c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))   # children do not inherit runtime .libPaths()
  code <- "p <- commandArgs(TRUE)[1]; r <- tryCatch({ suppressPackageStartupMessages(loadNamespace(p)); 'OK' }, error = function(e) paste('ERR', gsub('[[:space:]]+', ' ', conditionMessage(e)))); cat(substr(r, 1, 2000))"   # 2000, not 300: the dlopen path must survive for .gptr_short_load_error()
  res <- setNames(vector("list", length(pkgs)), pkgs)
  queue <- pkgs; running <- list()
  while (length(queue) || length(running)) {
    while (length(queue) && length(running) < max_parallel) {
      p <- queue[1]; queue <- queue[-1]
      running[[p]] <- list(proc = processx::process$new(rscript, c("--vanilla", "-e", code, p), env = env,
                                                        stdout = "|", stderr = "|"), t0 = Sys.time())
    }
    for (p in names(running)) {
      pr <- running[[p]]$proc
      if (!pr$is_alive() || difftime(Sys.time(), running[[p]]$t0, units = "secs") > timeout) {
        if (pr$is_alive()) { pr$kill(); out <- "ERR timeout" } else out <- paste(pr$read_all_output(), collapse = "")
        if (!nzchar(out)) out <- paste("ERR exit status", pr$get_exit_status(), substr(gsub("[[:space:]]+", " ", paste(pr$read_all_error(), collapse = " ")), 1, 200))
        res[[p]] <- out; running[[p]] <- NULL
      }
    }
    Sys.sleep(0.05)
  }
  data.frame(pkg = pkgs, loadable = startsWith(unlist(res), "OK"),
             error = ifelse(startsWith(unlist(res), "OK"), NA_character_, sub("^ERR ", "", unlist(res))), row.names = NULL)
}

gptr_capabilities <- function(registry = gptr_perf_registry(), check_load = FALSE) {
  meta <- .gptr_pkg_meta(registry$pkg)
  caps <- merge(registry, meta, by = "pkg", sort = FALSE)
  caps <- caps[match(registry$pkg, caps$pkg), ]
  caps$installed <- !is.na(caps$version)
  caps$loaded <- caps$pkg %in% loadedNamespaces()
  caps$loadable <- ifelse(caps$loaded, TRUE, NA)
  caps$load_error <- NA_character_
  if (check_load) {
    todo <- caps$pkg[caps$installed & !caps$loaded & caps$compiled %in% "yes"]
    pr <- .gptr_probe_loadable(todo)
    i <- match(pr$pkg, caps$pkg)
    caps$loadable[i] <- pr$loadable; caps$load_error[i] <- pr$error
  }
  caps$loadable[caps$installed & is.na(caps$loadable) & caps$compiled %in% "no"] <- TRUE  # pure-R: assume loadable
  attr(caps, "session") <- list(
    r = as.character(getRversion()), platform = R.version$platform, os = .Platform$OS.type,
    utf8 = isTRUE(l10n_info()[["UTF-8"]]), cores = parallel::detectCores(logical = TRUE),
    ram_gb = tryCatch(round(ps::ps_system_memory()$total / 1024^3), error = function(e) NA),
    ram_free_gb = tryCatch(round(ps::ps_system_memory()$avail / 1024^3), error = function(e) NA),
    pcre_jit = isTRUE(pcre_config()[["JIT"]]))
  rownames(caps) <- NULL
  caps
}

.gptr_short_load_error <- function(e) {
  if (is.na(e)) return("load error")
  m <- regmatches(e, regexpr("Library not loaded: [^ ,]+", e))
  if (length(m)) return(paste("missing system library", basename(sub("Library not loaded: ", "", m))))
  m <- regmatches(e, regexpr("there is no package called [^ ]+", e))
  if (length(m)) return(paste("missing dependency", gsub("[^A-Za-z0-9.]", "", sub("there is no package called ", "", m))))
  substr(e, 1, 60)
}

## Compact system-prompt section. Versions are shortened to major.minor(.patch).
gptr_prompt_r_env <- function(caps, max_workers = NULL) {
  s <- attr(caps, "session")
  short_ver <- function(v) sub("^(\\d+\\.\\d+(\\.\\d+)?).*$", "\\1", gsub("-", ".", v))
  have <- caps[caps$installed & !(caps$loadable %in% FALSE), ]
  broken <- caps[caps$installed & caps$loadable %in% FALSE, ]
  missing <- caps[!caps$installed, ]
  by_cat <- split(paste(have$pkg, short_ver(have$version)), factor(have$cat, levels = unique(caps$cat)))
  by_cat <- by_cat[lengths(by_cat) > 0]
  cores_use <- if (!is.null(max_workers)) max_workers
               else if (nzchar(Sys.getenv("_R_CHECK_LIMIT_CORES_"))) 2L          # R CMD check --as-cran sets this
               else if (requireNamespace("parallelly", quietly = TRUE)) parallelly::availableCores(omit = 1L)  # honours cgroups/Slurm/mc.cores
               else max(1L, s$cores - 1L)
  lines <- c(
    sprintf("R %s, %s, %s locale%s; %d cores (use <= %d workers); RAM %s GB (%s GB free)", s$r, s$platform,
            if (s$utf8) "UTF-8" else "NON-UTF-8", if (s$pcre_jit) ", PCRE JIT" else "", s$cores, cores_use, s$ram_gb, s$ram_free_gb),
    paste0("Installed: ", paste(sprintf("%s: %s", names(by_cat), vapply(by_cat, paste, "", collapse = ", ")), collapse = "; ")),
    if (nrow(broken)) paste0("Installed but NOT loadable (do not library() them): ",
                             paste(sprintf("%s (%s)", broken$pkg, vapply(broken$load_error, .gptr_short_load_error, "")), collapse = "; ")),
    paste0("Not installed (ask before installing; ", "Bioc = BiocManager, GitHub = remotes): ",
           paste(ifelse(missing$repo == "CRAN", missing$pkg, sprintf("%s[%s]", missing$pkg, missing$repo)), collapse = ", ")))
  paste0("<r_env>\n", paste(lines, collapse = "\n"), "\n</r_env>")
}

## ---- demo -------------------------------------------------------------------------------------
if (sys.nframe() == 0L) {
  t_fast <- system.time(caps <- gptr_capabilities(check_load = FALSE))[["elapsed"]]
  cat("fast detection (no loading):", t_fast, "s\n")
  print(caps[, c("pkg", "cat", "installed", "version", "compiled", "loaded", "loadable")], row.names = FALSE)
  block <- gptr_prompt_r_env(caps)
  cat("\n", block, "\n\nchars:", nchar(block), " ~tokens(chars/4):", ceiling(nchar(block) / 4), "\n", sep = "")
  t_probe <- system.time(caps2 <- gptr_capabilities(check_load = TRUE))[["elapsed"]]
  cat("\nwith out-of-process load probe of compiled, not-yet-loaded packages:", t_probe, "s\n")
  print(caps2[caps2$installed, c("pkg", "compiled", "loadable", "load_error")], row.names = FALSE)
  block2 <- gptr_prompt_r_env(caps2)
  cat("\n", block2, "\n\nchars:", nchar(block2), " ~tokens(chars/4):", ceiling(nchar(block2) / 4), "\n", sep = "")
}
```

Observed (`$W/out_proto_caps.txt`): `fast detection (no loading): 0.149 s`; probe took 29.051 s and
reported `loadable TRUE` for all 23 probed packages except `BPCells FALSE` with error
"unable to load shared object … Library not loaded: /opt/homebrew/opt/hdf5/lib/libhdf5.310.dy…";
rendered block as shown in §3.2 (the §3.2 text comes from the final version with
`.gptr_short_load_error`, `$W/out_proto_caps_prompt.txt`). **Verifier correction:** the code as
originally published truncated the child's error at 300 characters (`cat(substr(r, 1, 300))`), which
cuts the BPCells message inside the file name, so the rendered line was "missing system library
libhdf5.310.dy" (reproduced) instead of §3.2's "libhdf5.310.dylib". With the limit raised to 2000
(as now shown above) the re-run reproduces §3.2 exactly (866 chars). Two bugs found and fixed while building it:
`Rscript -e code --args p` passes a literal `--args` to `commandArgs(TRUE)` (use `Rscript -e code p`),
and backslash escapes inside the `-e` string are fragile (use `[[:space:]]`).

### 5.13 Harness helper prototypes `proto_harness_helpers.R` (complete; run in UTF-8 and C locales)

```r
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-19/common.R")

## 1. Streaming text buffer: closure + `<<-` (linear); never `env$vec[i] <- x` inside a callback (quadratic copy).
stream_buffer <- function(initial = 256L) {
  buf <- character(initial); n <- 0L
  list(
    push = function(x) { n <<- n + 1L; if (n > length(buf)) length(buf) <<- 2L * length(buf); buf[n] <<- x; invisible(NULL) },
    text = function() paste(buf[seq_len(n)], collapse = ""),
    n    = function() n)
}

## 2a. Encoding guard: in a non-UTF-8 (e.g. C) locale, jsonlite writes non-ASCII bytes of 'unknown'-encoded
##     strings as literal "<c3><a9>". Mark valid UTF-8 as UTF-8 (C/ASCII locale), or convert native -> UTF-8.
as_utf8_deep <- function(x) {
  if (is.character(x)) {
    if (isTRUE(l10n_info()[["UTF-8"]])) return(x)
    unk <- !is.na(x) & Encoding(x) == "unknown" & grepl("[^\\x01-\\x7f]", x, perl = TRUE, useBytes = TRUE)
    if (any(unk)) {
      native_is_ascii <- toupper(l10n_info()[["codeset"]]) %in% c("US-ASCII", "ANSI_X3.4-1968", "C", "POSIX")
      ok <- unk & validUTF8(x)
      if (native_is_ascii) Encoding(x[ok]) <- "UTF-8" else x[unk] <- enc2utf8(x[unk])
    }
    return(x)
  }
  if (is.list(x)) { a <- attributes(x); x <- lapply(x, as_utf8_deep); attributes(x) <- a }
  x
}
## 2b. Per-message JSON cache + request assembly with json_verbatim (identical bytes to a full toJSON).
msg_json <- function(msg) structure(as.character(jsonlite::toJSON(as_utf8_deep(msg), auto_unbox = TRUE, null = "null", digits = NA)), class = "json")
request_body <- function(fields, msg_cache) {
  fields$messages <- structure(paste0("[", paste(unlist(msg_cache, use.names = FALSE), collapse = ","), "]"), class = "json")
  as.character(jsonlite::toJSON(fields, auto_unbox = TRUE, null = "null", digits = NA, json_verbatim = TRUE))
}

## 3. Append-only JSONL session writer with a kept-open connection (flush per entry).
jsonl_writer <- function(path) {
  con <- file(path, open = "ab")
  list(append = function(entry_json) { writeLines(entry_json, con, useBytes = TRUE); flush(con); invisible(TRUE) },
       close = function() close(con))
}

## 4. Read text as UTF-8-marked (safe for JSON in any locale); invalid UTF-8 kept as bytes with a flag.
read_text_utf8 <- function(path, n = -1L) {
  x <- readLines(path, n = n, warn = FALSE, encoding = "UTF-8", skipNul = TRUE)
  bad <- !validUTF8(x)
  if (any(bad)) x[bad] <- iconv(x[bad], "UTF-8", "UTF-8", sub = "�")   # replace invalid bytes
  x
}

## 5. base64 without line breaks (jsonlite::base64_enc inserts "\n" every 72 chars).
b64_encode <- function(raw) gsub("\n", "", jsonlite::base64_enc(raw), fixed = TRUE)

## 6. Content fingerprint for stale-edit detection.
file_fingerprint <- function(path) if (requireNamespace("rlang", quietly = TRUE)) rlang::hash_file(path) else unname(tools::md5sum(path))

## ---- tests -------------------------------------------------------------------------------------
set.seed(1)
d <- vapply(1:50000, function(i) paste(sample(c(letters, " ", "é"), sample(1:30, 1), TRUE), collapse = ""), "")
sb <- stream_buffer(); t <- system.time(for (x in d) sb$push(x))[["elapsed"]]
cat("stream_buffer: 50000 pushes in", t, "s; identical:", identical(sb$text(), paste(d, collapse = "")), "\n")
msgs <- lapply(1:200, function(i) list(role = if (i %% 2) "user" else "assistant", content = list(list(type = "text", text = paste("méssage", i, "\"q\"\n")))))
cache <- lapply(msgs, msg_json)
fields <- list(model = "m", max_tokens = 1024L, stream = TRUE, system = "sys")
full <- as.character(jsonlite::toJSON(as_utf8_deep(c(fields, list(messages = msgs))), auto_unbox = TRUE, null = "null", digits = NA))
cat("request_body identical to full toJSON:", identical(request_body(fields, cache), full), "\n")
show(bench::mark(full = jsonlite::toJSON(c(fields, list(messages = msgs)), auto_unbox = TRUE, null = "null", digits = NA),
                 cached = request_body(fields, cache), check = FALSE, min_iterations = 20, filter_gc = FALSE), "200-message body")
tf <- tempfile(fileext = ".jsonl"); w <- jsonl_writer(tf)
for (m in cache) w$append(m); w$close()
back <- lapply(readLines(tf, encoding = "UTF-8"), jsonlite::parse_json)
cat("JSONL round trip identical:", identical(back, as_utf8_deep(msgs)), "  bytes of first text in file:", paste(as.character(charToRaw(back[[1]]$content[[1]]$text))[1:4], collapse = " "), "\n")
tf2 <- tempfile(); writeBin(c(charToRaw("ok caf\xc3\xa9\n"), as.raw(c(0x62, 0x61, 0x64, 0xff, 0x0a))), tf2)
r <- read_text_utf8(tf2); cat("read_text_utf8:", Encoding(r), "| valid:", validUTF8(r), "| json:", jsonlite::toJSON(r), "\n")
img <- as.raw(sample(0:255, 3e5, TRUE))
cat("b64_encode == base64enc:", identical(b64_encode(img), base64enc::base64encode(img)), " no newline:", !grepl("\n", b64_encode(img), fixed = TRUE), "\n")
cat("fingerprint changes on edit:", { a <- file_fingerprint(tf2); cat("x\n", file = tf2, append = TRUE); a != file_fingerprint(tf2) }, "\n")
```

(In the file on disk the `é` and `�` appear as literal UTF-8 characters.) Observed:

```text
=== UTF-8 locale
stream_buffer: 50000 pushes in 0.056 s; identical: TRUE
request_body identical to full toJSON: TRUE
### 200-message body
 full    13.3ms  15.5ms ... rel 55.7
 cached 268.5µs 279.1µs ... rel 1.0
JSONL round trip identical: TRUE   bytes of first text in file: 6d c3 a9 73
read_text_utf8: UTF-8 UTF-8 | valid: TRUE TRUE | json: ["ok café","bad�"]
b64_encode == base64enc: TRUE  no newline: TRUE
fingerprint changes on edit: TRUE
=== C locale (LANG=C LC_ALL=C)
stream_buffer: 50000 pushes in 0.065 s; identical: TRUE
request_body identical to full toJSON: TRUE
 full 15.5ms | cached 273.1us
JSONL round trip identical: TRUE   bytes of first text in file: 6d c3 a9 73
read_text_utf8: UTF-8 UTF-8 | valid: TRUE TRUE | json: ["ok caf<U+00E9>","bad<U+FFFD>"]    # display only; bytes are UTF-8
b64_encode == base64enc: TRUE  no newline: TRUE
fingerprint changes on edit: TRUE
```

Before the `as_utf8_deep()` guard was added, the C-locale run printed
`JSONL round trip identical: FALSE` (the source literal `méssage` is unknown-encoded in a C locale and
jsonlite wrote `m<c3><a9>ssage`; see `$W/b14e_c_locale_literal.R`).

### 5.14 Encoding bytes `b14d_locale_bytes.R`

```r
cat("LC_CTYPE:", Sys.getlocale("LC_CTYPE"), "\n")
hex <- function(s) paste(as.character(charToRaw(s)), collapse = " ")
tf <- tempfile(); writeBin(charToRaw("caf\xc3\xa9\n"), tf)
cases <- list(
  utf8_marked            = { x <- rawToChar(charToRaw("caf\xc3\xa9")); Encoding(x) <- "UTF-8"; x },
  readLines_default      = readLines(tf),
  readLines_encoding_utf8= readLines(tf, encoding = "UTF-8"),
  capture_print_marked   = { x <- rawToChar(charToRaw("caf\xc3\xa9")); Encoding(x) <- "UTF-8"; capture.output(print(x)) },
  system2_output         = system2("printf", shQuote("caf\\303\\251"), stdout = TRUE))
for (nm in names(cases)) {
  s <- cases[[nm]]; j <- as.character(jsonlite::toJSON(s, auto_unbox = TRUE))
  cat(sprintf("%-24s Encoding=%-8s value bytes=[%s]  json bytes=[%s]\n", nm, Encoding(s), hex(s), hex(j)))
}
```

```text
=== C
LC_CTYPE: C
utf8_marked              Encoding=UTF-8    value bytes=[63 61 66 c3 a9]  json bytes=[22 63 61 66 c3 a9 22]
readLines_default        Encoding=unknown  value bytes=[63 61 66 c3 a9]  json bytes=[22 63 61 66 3c 63 33 3e 3c 61 39 3e 22]
readLines_encoding_utf8  Encoding=UTF-8    value bytes=[63 61 66 c3 a9]  json bytes=[22 63 61 66 c3 a9 22]
capture_print_marked     Encoding=unknown  value bytes=[5b 31 5d 20 22 63 61 66 3c 55 2b 30 30 45 39 3e 22]  json bytes=[...]
system2_output           Encoding=unknown  value bytes=[63 61 66 c3 a9]  json bytes=[22 63 61 66 3c 63 33 3e 3c 61 39 3e 22]
=== UTF-8
(all five cases: json bytes contain c3 a9)
```

### 5.15 Other executed checks

- `b11_api_check.R`: every function named in the skill/decision table exists and is exported in the
  installed versions (data.table 16/16, arrow 11/11, duckplyr 11/11, collapse 18/18, qs2 11/11,
  kit 10/10, mirai 9/9, targets 10/10, Seurat 22/22, …), except `SeuratObject::SplitLayers`
  (not exported) and `tools::sha256sum` (R ≥ 4.5). BPCells checked from its `NAMESPACE` file.
- `b13_formals.R`: argument names used in the skill verified, e.g.
  `kit::topn(vec, n, decreasing, hasna, index)`,
  `scattermore::geom_scattermore(..., interpolate, pointsize, pixels)`,
  `qs2::qs_save(object, file, compress_level, shuffle, nthreads)`,
  `duckplyr::read_parquet_duckdb(path, ..., prudence, options)`,
  `mirai::mirai_map(.x, .f, ..., .args, .promise, .compute)`,
  `mirai::everywhere(.expr, ..., .args, .min, .compute)`,
  `HDF5Array::writeHDF5Array(x, filepath, name, H5type, chunkdim, level, as.sparse, with.dimnames, verbose)`,
  `vroom::vroom_lines(file, n_max, skip, na, skip_empty_rows, locale, altrep, num_threads, progress)`,
  `stringi::stri_opts_collator(locale, strength, …, numeric)`, `future.mirai` exports `mirai_multisession`.
- `test_skill_recipes.R` (extracts every ```` ```r ```` block from the skill files and runs each in a fresh
  `Rscript --vanilla` with `setwd(tempdir())`):

```text
blocks found: 18
 references/parallel-and-pipelines.md  37 # mirai                  TRUE  1.1 s
 references/parallel-and-pipelines.md  45 # future + future.apply   TRUE  1.6
 references/parallel-and-pipelines.md  52 # base R, portable        TRUE  0.6
 references/parallel-and-pipelines.md  60 # BiocParallel           TRUE  1.2
 references/parallel-and-pipelines.md  65 # targets ...             TRUE  2.7
 references/single-cell.md             17 # BPCells (commented)     TRUE  0.2
 references/single-cell.md             26 # Seurat v5 layers        TRUE 10.6
 references/single-cell.md             43 SingleCellExperiment      TRUE 12.2
 SKILL.md  78 delimited files TRUE | 89 parquet/duckdb/arrow TRUE | 110 data.table TRUE | 125 collapse TRUE | 135 strings TRUE
 SKILL.md 145 sorting TRUE | 154 saving objects TRUE | 167 matrices TRUE | 181 profiling TRUE (bench GC warning) | 191 plotting TRUE
PASSED 18 of 18
```

(Verifier note: "TRUE" means "no R error". The mirai block's TRUE was a false pass — every element
was a `miraiError`; the recipe has been corrected in §3.4.2 and the corrected call re-verified.)

- `b16_deps.R`, `b17_grep_tool.R`, `b15_objsize.R`: outputs quoted in §2.4 / §4.5.

Not executed: anything on Windows or Linux; BPCells code (package not loadable here); polars;
interactive `profvis`; Seurat with BPCells-backed layers; duckdb larger-than-RAM spilling at scale;
`purrr::in_parallel` (purrr 1.2.2 installed, not run).

---

## 6. CRAN and cross-platform considerations (Windows in particular)

- **Cores during checks.** Tests/examples of gptr itself must use ≤ 2 workers; derive the cap from
  `_R_CHECK_LIMIT_CORES_` (set by `--as-cran`) or `parallelly::availableCores()` when installed. The
  `<r_env>` worker hint must use the same logic so the agent never proposes more under check.
- **No writes outside `tempdir()` by default.** The load-probe cache belongs in
  `tools::R_user_dir("gptr", "cache")` only after consent (D-10). duckdb's default spill directory is
  `.tmp` in the working directory; any gptr example or test that opens duckdb must `SET
  temp_directory` under `tempdir()`.
- **Do not call installers.** Package code must never run `install.packages()` itself; the agent may
  propose it, gated by the permission system (§4.3).
- **Suggests are optional at run time.** Every use of vroom/stringi/lobstr/parallelly must be guarded
  with `requireNamespace(pkg, quietly = TRUE)`; tests that need them use `skip_if_not_installed()`.
  Note that `requireNamespace()` loads the namespace (fine for these light packages; never for the
  steering registry — use §4.2).
- **Windows specifics:**
  - No fork: `mclapply(mc.cores > 1)` fails and `plan(multicore)` falls back to sequential. Workers
    must be PSOCK/processx/mirai (all verified on macOS; Windows behaviour from docs: LIKELY).
  - Executable name: `Rscript.exe` under `R.home("bin")` (the prototype handles it); `.Platform$path.sep`
    is `;` when building `R_LIBS`.
  - R ≥ 4.2 on Windows uses UTF-8 natively via UCRT (Windows 10 November 2019+); on older Windows the
    session is in a legacy code page, so `as_utf8_deep()` converts native → UTF-8 (`enc2utf8`) there.
  - Long paths (> 260 chars) work only when the OS setting `LongPathsEnabled` is on (R ≥ 4.3 is
    long-path aware); the find/grep tools should report, not crash on, path errors.
  - `list.files()`/`file.info()` speeds on NTFS were not measured (UNCERTAIN); antivirus scanning can
    dominate file-heavy tools.
  - PCRE JIT availability on Windows builds: UNCERTAIN; the harness does not depend on it.
  - `system2("grep")`/`printf` etc. do not exist on Windows: the grep tool must stay pure R (it is
    already as fast as system grep).
- **macOS/Linux:** compiled packages linked against Homebrew/system libraries break silently when the
  system library is upgraded (BPCells/libhdf5 here); combined with the R < 4.6.1 `dyn.load` bug this
  can crash the live session — hence the child-process probe.
- **C locale:** CI runners, cron and some IDE launchers start R without `LANG`. Warn once at session
  start if `!l10n_info()[["UTF-8"]]` and apply the encoding guard everywhere text becomes JSON.

---

## 7. Risks, pitfalls, open questions

Risks and pitfalls (all VERIFIED unless marked):
1. **Benchmark noise**: heavy concurrent load (load average up to 72). Ratios are robust across
   repeated runs; absolute numbers are pessimistic. Multi-threaded results (data.table GForce mean at
   4 threads, arrow, duckdb) are the least reliable.
2. **Older benchmark versions**: qs2 0.1.7 (current 0.3.1), duckdb 1.5.0 (1.5.6), collapse 2.1.6
   (2.1.8), mirai 2.6.1 (2.7.3), arrow 23 (25). Conclusions about relative speed are unlikely to flip
   (LIKELY), but the skill's API usage should be re-validated against current versions in gptr's CI.
3. **The callback-copy mechanism is not understood** (UNCERTAIN why a called function duplicates
   `env$vec` but the inline loop does not). The rule and the fix are verified; add a regression
   benchmark to gptr's test suite (skip on CRAN) so a future refactor does not reintroduce it.
4. **Capability data is a snapshot**: packages installed by the agent or user mid-session must
   trigger a refresh; a stale `<r_env>` could make the model avoid an installed package or try a
   missing one (the base fallback keeps it safe).
5. **Load probe cost**: ~30 s for ~25 compiled packages on a loaded machine (each Seurat/Bioc load
   is 2–9 s). Run it in the background, only for unloaded compiled packages, only on R < 4.6.1 or
   on demand, and cache it.
6. **`installed ≠ loadable` also holds for pure-R packages** whose dependencies are missing or
   broken (e.g. a pure-R package importing BPCells). The prototype assumes pure-R packages load;
   the probe could include them when their dependencies include a known-broken package (open).
7. **Skill staleness**: the skill hard-codes facts that change (qs archived, polars off CRAN,
   duckplyr prudence threshold of 1,000,000 cells, Seurat defaults). Version the skill and re-run
   `test_skill_recipes.R` in gptr's CI (not on CRAN).
8. **Prompt budget**: `<r_performance>` (~300–390 tokens) + `<r_env>` (~220 tokens) ≈ 0.6k tokens
   per request; acceptable, but make both sections removable via the section registry (REQ-31).
9. **Token counts are estimates** (chars/4 and words×1.35); no tokenizer was available offline.
10. **yyjsonr temptation**: it is 40–90x faster at serialising, but array simplification would
    silently corrupt JSON Schemas (`required`) and tool arguments; do not adopt it without a schema-
    aware wrapper and exhaustive round-trip tests.

Open questions:
- Should gptr expose `gptr_capabilities()` to users (e.g. `/env` slash command) or keep it internal?
- Should the steering registry be user-extensible (e.g. a lab's own packages) via `.gptr/` settings
  or extensions (D-16)?
- Should the harness pre-emptively set `data.table::setDTthreads()` / duckdb threads when it runs
  sub-agent workers in parallel (D-12), or only advise the model?
- Does gptr need string hashing on R < 4.5 at all (cache keys can use `rlang::hash`)? If the auth
  track Imports openssl, `openssl::sha256()` is an alternative for cryptographic needs.
- Windows timings for list/stat/grep and PCRE JIT status need a Windows run (CI job on
  `windows-latest`).

---

## 8. Sources

Local (read first-hand):
- Pi `packages/coding-agent/src/core/system-prompt.ts` lines 9–216 (section model, rules, skills).
- Pi `packages/coding-agent/src/core/tools/{read,bash,edit,write,ls,find,grep,powershell}.ts`
  prompt contributions (read.ts:20-23, bash.ts:45-48, edit.ts:43-51, write.ts:16-19, ls.ts:16-19,
  find.ts:34-37, grep.ts:35-38, powershell.ts:18-21); `packages/coding-agent/src/extensions/codemode/tool.ts:124-129`
  (under `src/extensions/`, not `src/core/`).
- Pi `packages/coding-agent/src/core/extensions/types.ts:567-570`; `agent-session.ts:1601-1620, 3440-3463`.
- Pi `packages/coding-agent/src/core/skills.ts:11-14, 95-127, 355-392`.
- Pi `packages/ai/src/utils/text.ts:15-40`.
- gptr `dev/spec/00-vision-brief.md`, `dev/spec/01-decision-register.md`.
- Installed R help: `?sort` (radix), `?data.table::setDTthreads`, `?future::multicore`,
  `?future::future.options`, `?parallel::mclapply`, `?Seurat::DimPlot`; printed sources of
  `httr2::req_body_json`, `rlang::is_installed`, `rlang:::detect_installed`; `BPCells/NAMESPACE`.

Web:
- CRAN package pages: https://cran.r-project.org/package=qs (archived 2026-01-17),
  https://cran.r-project.org/package=polars (archived 2023-07-18), https://cran.r-project.org/package=qs2
- qs2 README: https://cran.r-project.org/web/packages/qs2/readme/README.html
- R release banner: https://cran.r-project.org/banner.shtml (R 4.6.1, 2026-06-24)
- R NEWS: https://cran.r-project.org/doc/manuals/r-release/NEWS.html (4.5.0 `sha256sum`, `md5sum(bytes=)`;
  4.6.1 PR#19029 dyn.load fix)
- `tools::md5sum` (R-devel help): https://stat.ethz.ch/R-manual/R-devel/library/tools/html/md5sum.html
- CRAN Repository Policy: https://cran.r-project.org/web/packages/policies.html
- R Internals, Tools (`_R_CHECK_LIMIT_CORES_`): https://rstudio.github.io/r-manuals/r-ints/Tools.html
- Bioconductor: https://bioconductor.org/ and https://bioconductor.org/install/ (3.23, R 4.6.0)
- BPCells: https://bnprks.github.io/BPCells/ ; Seurat + BPCells vignette:
  https://satijalab.org/seurat/articles/seurat5_bpcells_interaction_vignette
- r-polars: https://rpolars.r-universe.dev/polars/doc/readme , https://rpolars.r-universe.dev/polars
- nanoparquet: https://nanoparquet.r-lib.org/
- duckplyr: https://duckplyr.tidyverse.org/ , https://duckplyr.tidyverse.org/articles/telemetry.html
- DuckDB: https://duckdb.org/docs/current/guides/performance/how_to_tune_workloads.html ,
  https://duckdb.org/docs/current/configuration/overview.html
- purrr `in_parallel()`: https://purrr.tidyverse.org/reference/in_parallel.html
- R on Windows UTF-8/UCRT: https://blog.r-project.org/2022/11/07/issues-while-switching-r-to-utf-8-and-ucrt-on-windows/
- Windows path length: https://blog.r-project.org/2023/03/07/path-length-limit-on-windows/
- PCRE JIT background (not decisive): https://www.pcre.org/original/doc/html/pcrejit.html

Executed evidence: every `$W/b*.R`, `$W/proto_*.R`, `$W/test_skill_recipes.R`, `$W/cran_status2.R` with
the matching `$W/out_*.txt` files.

---

## Verification log

Independent fact-check, 2026-09-29/30 (UTC 02:57 for CRAN metadata). All re-runs used
`Rscript --vanilla` (R 4.4.3, macOS arm64, heavily loaded machine), the private CRAN library
`scratchpad/rlib` via `R_LIBS`, and scripts/outputs in
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/verify-19/`
(`v1_basics.R` … `v15_plots_mirai_fix.R`, `out_v*.txt`). No prior verify-19 scratch existed. The
§5.12/§5.13/§5.14/§5.3 prototypes were extracted **from this report's text** (they match the
`$W` files except for comments) and the §3.4 skill blocks were extracted from the report and run.

| # | Claim | Verdict | Source / method |
|---|---|---|---|
| 1 | Pi section model: `/^[a-z][a-z0-9_-]*$/` (l.52), no `preamble` (l.137), wrapping `<name>…</name>` (l.175–177), order preamble/tools/rules/docs/addendum/project_context/skills/cwd/custom, only `cwd` injected | confirmed | Pi `1b347794` `core/system-prompt.ts` (grep for OS/date: none) |
| 2 | Section patch text `Updated system prompt section "<name>":` and `diffSystemPromptSections` | confirmed | `packages/ai/src/utils/text.ts:28-40`; `system-prompt.ts:204-216` |
| 3 | `promptSnippet`/`promptGuidelines` fields; read/bash/edit snippets and guidelines; snippet one-line normalisation | confirmed | `extensions/types.ts:567-570`; `tools/read.ts:20-23`, `bash.ts:45-48`, `edit.ts:43-51`; `agent-session.ts:1601-1608` |
| 4 | Skill rules: name `^[a-z0-9-]+$`, ≤64, no edge/double hyphen; description required ≤1024; `<available_skills>` format and read-tool sentence | confirmed | `core/skills.ts:11-14, 95-127, 355-383` |
| 5 | Source path `extensions/codemode/tool.ts:124-129` | corrected (path is `src/extensions/…`, not under `core/`) | Pi clone |
| 6 | CRAN versions/dates for ~60 packages in §2.2 table (data.table 1.18.6.1 … lobstr 1.2.2, httr2 1.3.0, qs2 0.3.1, mirai 2.7.3, duckdb 1.5.6) | confirmed | `tools::CRAN_package_db()` (25,273 rows) |
| 7 | qs archived 2026-01-17; polars archived 2023-07-18 "for policy violations"; mirai.promises 2024 | confirmed | CRAN package pages |
| 8 | rasterly "archived 2020"; disk.frame "archived 2023"; tidypolars implied archived | corrected (2022-10-03; 2026-01-30; tidypolars never on CRAN) | CRAN package pages / 404 on CRAN archive |
| 9 | Bioconductor 3.23 works with R 4.6.0; BPCells not on CRAN/Bioc, 0.3.1 on R-universe | confirmed (current Bioc versions added to table) | bioconductor.org/install, Bioc package pages, bnprks.r-universe.dev API |
| 10 | R 4.6.1 current (2026-06-24); R 4.5.0 NEWS `sha256sum()` and `md5sum(bytes=)`; R 4.6.1 NEWS PR#19029 | confirmed | cran.r-project.org/banner.shtml; r-release NEWS.html |
| 11 | BPCells failed load then any compiled load segfaults (address 0x202c29656c696620) | confirmed (reproduced with jsonlite, data.table) | fresh `Rscript` runs |
| 12 | That crash "is PR#19029, fixed in R 4.6.1" | downgraded to LIKELY (no R 4.6.1 available to test) | NEWS text only |
| 13 | CRAN policy quotes (≤2 cores; no writes outside tempdir; `R_user_dir()` for R ≥ 4.0; Suggests used conditionally; compiled code never terminates R) | confirmed verbatim | cran.r-project.org/web/packages/policies.html |
| 14 | `_R_CHECK_LIMIT_CORES_` set by `--as-cran`; `parallelly::availableCores()` → 2 under it; `omit = 1` → 7 | confirmed | R Internals "Tools"; deparsed `tools:::.check_packages` (sets it to "TRUE" when unset); executed |
| 15 | `jsonlite::base64_enc()` inserts `\n` every 72 chars (first at 73); `gsub` fix equals base64enc | confirmed | executed (jsonlite 2.0.0) |
| 16 | httr2 `req_body_json()` defaults `auto_unbox = TRUE, digits = 22, null = "null"` | confirmed (also 1.3.0 docs) | printed source 1.2.2; httr2.r-lib.org reference |
| 17 | `rlang::is_installed()` loads the namespace | confirmed (matrixStats loaded after the call) | executed; `rlang:::detect_installed` source |
| 18 | Cached per-message JSON + `json_verbatim = TRUE` is byte-identical; speed-up "12–68x" | identity confirmed; ratio corrected to ~10–55x (68x not in the report's own data) | re-ran §5.3 (9.5x, 15x) and §5.13 (79–161x, noisy) |
| 19 | JSONL append via kept-open connection ≪ rewrite | confirmed (13.8 µs vs 121 ms) | re-ran §5.3 |
| 20 | yyjsonr simplifies `["path"]` → `"path"`, big ints → string, `NULL` → `[]`; simdjson `{}`/`[]` → `NULL`; `parse_json` default `simplifyVector = FALSE` | confirmed | `v14_json_edge.R` |
| 21 | `env$buf[n] <- x` inside a called function copies (143 MB / 5,000); inline 294 KB; closure `<<-` linear; `stream_buffer` 50k pushes identical | confirmed | `v6_strings.R` |
| 22 | TRE "10–47x" slower than PCRE | corrected to ~6–55x (report data), 8–75x (re-run); direction confirmed; all engines agree; `gregexpr` 1.54 GB confirmed | `v10_regex.R` |
| 23 | `pcre_config()` JIT FALSE; PCRE 10.44, ICU 78.1, TRE 0.8.0 | confirmed | executed |
| 24 | `order()` on strings uses locale; radix byte order and ~40x faster; `kit::topn` ≫ `order()[1:10]`; `?sort` wording | confirmed (43x, 34x in re-run) | `v10_regex.R`, installed `?sort` |
| 25 | `glob2rx("**/*.qmd")` = `^.*.*/.*\.qmd$`; `list.files()` skips dot entries unless `all.files = TRUE`; ordering demo | confirmed | `v1_basics.R` |
| 26 | C locale: `toJSON()` writes unknown-encoded UTF-8 as literal `<c3><a9>`; UTF-8-marked fine; `enc2utf8()` does not help; `Rscript` without LANG is C | confirmed byte-for-byte | `rep_b14d.R` in C and UTF-8; `env -i` run |
| 27 | Harness helper prototype (§5.13) in UTF-8 and C locales | confirmed (all checks TRUE) | extracted from report and run |
| 28 | Capability prototype (§5.12) renders §3.2 `<r_env>` (866 chars, "libhdf5.310.dylib") | **corrected**: published code truncated the error at 300 chars → "libhdf5.310.dy"; fixed to 2000, re-run reproduces §3.2 exactly | `rep_proto_caps.R`, `v8_caps_fix.R` |
| 29 | Skill recipes: 18/18 pass | **corrected**: mirai recipe returned 8 `miraiError` values (named `...` are free variables, not args); fixed with `.args = list(k = 2)` + `[.stop]`; 18/18 re-run clean; `p2`/`p3` plots rendered | `v2_skill_recipes.R`, `v3_mirai.R`, `v15_plots_mirai_fix.R`; mirai.r-lib.org `mirai_map` docs (2.7.3) |
| 30 | duckplyr prudence: "more than 125,000 rows is an error" | **corrected**: limit is 1,000,000 cells (rows × columns) | `v5_duckplyr.R` (1/2/8 cols → 1e6/5e5/1.25e5 rows); duckplyr prudence article |
| 31 | duckplyr "telemetry uploads opt-in" | confirmed, but local collection is on by default (added) | duckplyr telemetry article; `?duckplyr::fallback` |
| 32 | `qd_save()` "refuses" language objects with a warning | **corrected**: it writes the file and drops them (`lm$call`, `$terms` → NULL) | executed with qs2 0.1.7; qs2 0.3.1 manual (`warn_unsupported_types`) |
| 33 | qs2 API `qs_save(object, file, compress_level, shuffle, nthreads)`, `qs_read(file, validate_checksum, nthreads)`; "not compatible with the original qs format"; Imports Rcpp/RcppParallel/stringfish | confirmed for 0.3.1 | CRAN qs2 README and 0.3.1 PDF manual; CRAN db |
| 34 | nanoparquet "Completely dependency free", no nested types/encryption/URLs, reads into memory | confirmed | nanoparquet.r-lib.org |
| 35 | DuckDB defaults: memory_limit 80% RAM, threads = cores, temp_directory `<db>.tmp` or `.tmp`, max_temp_directory_size 90% disk | confirmed | duckdb.org configuration overview |
| 36 | `future.globals.maxSize` default 500 MiB | confirmed | installed `?future.options` and `future:::getGlobalsAndPackages` |
| 37 | Seurat `DimPlot(raster = NULL)` auto-rasterises >100,000 cells via `geom_scattermore()`; `SketchData(ncells = 5000L, method = c("LeverageScore","Uniform"), sketched.assay = "sketch")`; `SplitLayers` not exported | confirmed | installed help (Seurat 5.4.0) |
| 38 | purrr ≥ 1.1.0 `in_parallel()` with named `...` on mirai daemons | confirmed; added that it needs Suggests `carrier (>= 0.3.0)` + `mirai (>= 2.5.1)` (call errored without carrier) | purrr.tidyverse.org; purrr 1.2.2 DESCRIPTION |
| 39 | Worker processes do not inherit runtime `.libPaths()`; `R_LIBS` fixes it | confirmed (reproduced the "initial sync with dispatcher" hang; child printed "no package called 'mirai'" to stderr) | `v12_mirai_libpaths.R` |
| 40 | `Rscript -e code --args p` yields `--args` in `commandArgs(TRUE)`; `processx` `env = c("current", …)` works | confirmed | `v1_basics.R` |
| 41 | Dependency counts: httr2 12, processx 2, callr 4 (incl. otel), vroom 21; union httr2+jsonlite+cli+processx = 16; mirai +2, later +2, promises +5 | confirmed | `tools::package_dependencies()` on current CRAN db |
| 42 | Windows UTF-8 via UCRT since R 4.2.0 (Windows 10 Nov 2019+); long-path aware from R 4.3 with `LongPathsEnabled` | confirmed | R blog 2022-11-07, 2023-03-07 |
| 43 | `<r_performance>` 1,569 chars / 219 words; skill description 537 chars; SKILL.md "230 lines / 15.1 KB" | chars/words confirmed; SKILL.md corrected to 232 lines / 15.3 KB | `v13_counts.R`; report skill text is identical to `$W/skill/` files |

Unverifiable here / left as measured: absolute timings (machine load average 8–48 during
verification; re-runs agree on direction and rough ratios but not absolute values, e.g. HDF5Array
load 4.9 s vs 9.15 s reported); anything on Windows/Linux; behaviour on R 4.6.1; BPCells and
Seurat-with-BPCells code; qs2 0.3.1 / duckplyr / mirai 2.7.3 behaviour at runtime (only their
docs were checked; runtime checks used the older private-library versions).
