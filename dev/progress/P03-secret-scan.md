# P03 Task 10: secret-access classifier

The classifier parses synthetic R code strings without evaluating them. It
reports secret environment reads, environment dumps, credential-file/keyring
access, vault access, environment writes, secret markers, network sinks and
tainted assignments. This static risk classification is advisory; it is not an
R sandbox or proof that arbitrary R code is safe.

Validation uses the outer-isolated runner, temporary HOME/XDG/R_USER directories,
the pinned development library and offline replay. No real environment values,
credential files or commands from the scanned strings are executed or read.

Actual command:
`R_LIBS_USER="$PWD/dev/.library" Rscript --vanilla dev/.validation/run-isolated.R test auth-secrets`.

- Missing-function red: FAIL 3 / WARN 0 / SKIP 0 / PASS 101.
- Baseline green: FAIL 0 / WARN 0 / SKIP 0 / PASS 194, including the plan's
  40 classification cases and its 1,000-statement bounded-time check.
- Additional regressions reproduced FAIL 10 / PASS 197 for reordered named
  `Sys.getenv()` arguments, literal name vectors, full shell/absolute executable
  network calls, replacement assignments and copied-variable taint.
- Those cases passed: FAIL 0 / WARN 0 / SKIP 0 / PASS 207. Static argument
  inspection never invokes the inspected functions. Container assignments taint
  their root symbol, and an assignment using existing taint propagates it.
- Portability regressions for `character(0L)` and Windows executable suffixes
  reproduced FAIL 2 / PASS 208, then passed all 210 assertions.
- Independent review found named/reordered `assign()` lost the actual tainted
  destination. Red: FAIL 4 / PASS 210; green after selecting named `x` before a
  positional fallback: PASS 214.
- Case-insensitive credential paths reproduced FAIL 2 / PASS 217, and uppercase
  `CURL.EXE` reproduced FAIL 1 / PASS 219. The finite path/executable patterns
  now conservatively recognize case variants; R function names stay case-sensitive.
- A final finite-command review added PowerShell `Get-ChildItem Env:`/`gci env:`,
  uppercase `SET` and a dump-to-network pipeline. Red: FAIL 8 / PASS 224. The
  known dump-command forms now recognize case variants and PowerShell's `Env:`
  path; ordinary echo, directory-listing and non-environment PowerShell commands
  stay unflagged by this secret classifier.
- Current final green: FAIL 0 / WARN 0 / SKIP 0 / PASS 232. Scoped source and
  mirrored-test lint: zero lints.

Raw logs remain ignored under `dev/.validation/P03-secret-scan/`. Independent
review repeated the named-assignment and shell-dump cases and cleared the final
implementation before the scoped commit. The process additionally reports
the installed testthat build-version warning (R 4.5.2 versus runtime 4.5.0),
outside the test-result warning count.
