# Isolated development tooling

Checked and installed on 2026-10-03 under deviation D-002. This is setup evidence,
not evidence that any package implementation or milestone gate has passed.

## Scope and source

The project-local library is `dev/.library/`, excluded from Git and R source
packages. No default or global R library was modified. Credentials were not read
or sourced. Installs ran sequentially with one compiler worker; the five missing
tools used macOS arm64 binary packages, so no DuckDB or tokenizer source build
was needed.

Official sources:

- Pinned roxygen2: <https://cran.r-project.org/src/contrib/Archive/roxygen2/roxygen2_7.3.3.tar.gz>
- Other packages: <https://cloud.r-project.org/bin/macosx/big-sur-arm64/contrib/4.5/>

## Commands and observed results

Run from the repository root. The commands below use a project-specific variable;
they do not change the user's persistent environment or startup files.

```sh
mkdir -p dev/.library
gptr_dev_library="$PWD/dev/.library"
curl --fail --location --max-time 60 \
  --output /private/tmp/gptr-roxygen2_7.3.3.tar.gz \
  https://cran.r-project.org/src/contrib/Archive/roxygen2/roxygen2_7.3.3.tar.gz
MAKEFLAGS=-j1 Rscript --vanilla -e \
  'install.packages("/private/tmp/gptr-roxygen2_7.3.3.tar.gz", repos = NULL,
    type = "source", lib = commandArgs(TRUE)[1], Ncpus = 1L)' "$gptr_dev_library"
R_LIBS_USER="$gptr_dev_library" MAKEFLAGS=-j1 Rscript --vanilla -e \
  'install.packages(c("chromote", "duckdb", "keyring", "rtiktoken", "spelling"),
    lib = commandArgs(TRUE)[1], repos = "https://cloud.r-project.org",
    type = "binary", Ncpus = 1L)' "$gptr_dev_library"
```

Results: roxygen2 completed with `* DONE (roxygen2)`; the binary installation
completed successfully. R's compiler headers produced a non-fatal warning about
an unknown `-Wfixed-enum-extension` warning group during the roxygen2 source
build. Each requested package subsequently loaded in its own clean R process.

| Package | Installed local version | Verification |
|---|---|---|
| roxygen2 | 7.3.3 | clean-process `loadNamespace()` passed; exact pin asserted |
| chromote | 0.5.1 | clean-process `loadNamespace()` passed |
| duckdb | 1.5.6 | clean-process `loadNamespace()` passed |
| keyring | 1.4.1 | clean-process `loadNamespace()` passed; no keychain accessed |
| rtiktoken | 0.11.0.3 | clean-process `loadNamespace()` passed |
| spelling | 2.3.2 | clean-process `loadNamespace()` passed |

Additional local dependencies installed from the same binary repository:
AsioHeaders 1.30.2-1, websocket 1.4.4, hunspell 3.0.6.

Verification commands:

```sh
for package_name in roxygen2 chromote duckdb keyring rtiktoken spelling; do
  R_LIBS_USER="$gptr_dev_library" Rscript --vanilla -e \
    'p = commandArgs(TRUE)[1]; invisible(loadNamespace(p));
     cat(p, as.character(packageVersion(p)), find.package(p), "LOAD_OK\n")' \
    "$package_name" || exit 1
done
R_LIBS_USER="$gptr_dev_library" Rscript --vanilla -e \
  'stopifnot(as.character(packageVersion("roxygen2")) == "7.3.3")'
git check-ignore dev/.library/roxygen2/DESCRIPTION dev/LOCAL_SETUP.md
```

All six packages reported `LOAD_OK` from `dev/.library`; both ignore checks
matched. A separate process without the local-library override still found the
original default-library roxygen2 8.1.0.

## How implementation commands select the tools

Prepend `R_LIBS_USER="$PWD/dev/.library"` to every `Rscript --vanilla` command,
including `devtools::document()`, so the pinned roxygen2 is used. `--vanilla`
does not disable the process environment variable. Scripts started from another
directory need the absolute project-local library path. Child processes that
sanitize their environment must preserve the intended `.libPaths()`/`R_LIBS`
through their documented mechanism.

## Remaining compatibility checks

- The eight required Imports meet their planned floors; all declared Suggests
  and the named release/development packages are now installed.
- The token baselines were recorded using rtiktoken 0.0.7; 0.11.0.3 is installed.
  P07's first token gate must validate actual counts. Installation and namespace
  loading do not establish tokenizer-baseline compatibility.
- Current R, lintr, knitr, rmarkdown and several other dependencies differ from
  the old plan-validation environment. Exact test counts and lint results must
  be established by the implementation gates rather than assumed.
- Quarto CLI remains absent and optional; its P15 integration test may skip.
- Python with pandas is present, but P22 must select the existing interpreter
  explicitly before testing reticulate; no automatic runtime download occurred.
- Chrome is present. The Shiny/chromote session ladder has not run yet.
- No live model, CLI authentication, cross-platform, or release gate was run
  during this setup. Machine-specific inventory remains in ignored
  `dev/LOCAL_SETUP.md`.

## Reusable isolated validation runner

`dev/ci/isolated-check.R` sets fresh home, configuration, cache, data and project
paths before any package load, clears known provider credential environment
variables, and disables live tests. Select `test <filter>`, `lint [files ...]`,
`document`, `connections`, or `check <output-directory>`. Use the absolute
project-local R library when validating a Git archive outside this checkout.
The connection action explicitly executes the full suite inside the checked
scope; sourcing the gate file alone does not execute its main entry point.
The connection gate uses IC-60 check-mode supervision and restores its option;
its expanded harness tests passed 9 assertions, including the real leaked-file
negative control and restoration after errors.
