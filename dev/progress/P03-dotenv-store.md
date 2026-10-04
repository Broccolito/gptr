# P03 Tasks 6–8: dotenv and credential store

All validation uses synthetic credentials and temporary files. The isolated
runner sets HOME, XDG, R_USER directories and the project root before package
loading, with `GPTR_REPLAY=replay` and `GPTR_LIVE_TESTS=false`. No real `.secrets`
files or user credential stores are read. Raw logs stay ignored under
`dev/.validation/P03-dotenv-store/`.

## Task 6: parser and aliases

The parser reads bytes, accepts BOM/CRLF, CP1252 fallback, quoted and multiline
values, export prefixes and comments, and rejects binary or missing files.
Canonical environment names include the built-in Jev aliases and registered
extension aliases.

Actual test command:
`R_LIBS_USER="$PWD/dev/.library" Rscript --vanilla dev/.validation/run-isolated.R test auth-dotenv`.
Red: FAIL 3 / WARN 0 / SKIP 0 / PASS 0, missing parser and alias functions.
Baseline green: FAIL 0 / WARN 0 / SKIP 0 / PASS 20.
New parser/alias regressions then reproduced FAIL 8 / PASS 20: a malformed
quoted suffix consumed later valid assignments, custom destinations were not
canonicalized, and malformed alias entries were accepted. The parser now stops
at the closing quote before validating its suffix, and alias definitions are
validated before mapping. Green after these fixes: FAIL 0 / WARN 0 / SKIP 0 /
PASS 29 (including an empty-alias-list control).
Independent review found that `EMPTY=   # comment` lost its separator whitespace
too early and treated the comment as a value. Paired with `DIRECT=#literal`, its
regression reproduced FAIL 1 / PASS 29. The parser now recognizes the comment
before trimming separator whitespace. Final green: FAIL 0 / WARN 0 / SKIP 0 /
PASS 30. Final scoped source/test lint: zero lints. Independent review cleared
the parser/alias changes and the final empty-comment regression before commit.

The R process additionally reports the installed testthat build-version warning
(built under R 4.5.2, running R 4.5.0); it is outside test-result warnings.

## Task 7: explicit loading and trusted-project discovery

Task 6 committed as `a978d1d`. The Task 7 tests first reproduced FAIL 7 / WARN 0 /
SKIP 0 / PASS 30 for the missing loader and discovery functions. Using the real
Task 1 vault and Task 2 redactor, the baseline then passed 89 assertions.

Additional regressions reproduced FAIL 5 / PASS 91. The loader now gives the
literal canonical spelling precedence over lowercase/canonicalized names, and
vault discovery preserves `.gptr/.env` precedence over `.env`. Secret-source
resolution no longer reactivates invalid API-key values that the loader refused;
they stay registered only for redaction. An explicitly empty selected value
also cannot fall through to an alias, and plain URL/path fields are not secret
source results. Green after these fixes: FAIL 0 / WARN 0 / SKIP 0 / PASS 96.

Independent review added the case where a higher-priority `.gptr/.env` defines
an empty or invalid key while `.env` defines a valid one. The regression failed
2 assertions (100 passed). Superseded values from that dotenv source now become
inactive while staying available for redaction; lookup no longer falls back to
the lower file. Current green: FAIL 0 / WARN 0 / SKIP 0 / PASS 102.

The owner of `auth-secrets.R` integrated the `secret_discover_env()` amendment
while preserving Task 1 review fixes; its focused 101 assertions remained green.
Independent review cleared Task 7. Pinned roxygen2 regenerated `gptr_env.Rd` and
its export/method declarations in an isolated process. The final combined
dotenv/store/vault run passed 263 assertions with zero failures/test warnings and
one skip (missing-keyring branch on a machine where keyring is installed).
Task 7 committed as `bccad62`; the `auth-secrets.R` owner can resume its other
tasks. The commit contains only the agreed discovery function change from that
file and only `gptr_env` namespace/manual entries.

## Task 8: credential store

Actual missing-function red: FAIL 6 / WARN 0 / SKIP 1 / PASS 0. Baseline green:
FAIL 0 / WARN 0 / SKIP 1 / PASS 33. The skip is the missing-keyring path because
keyring is installed. The positive keyring check uses its temporary environment
backend, without accessing the system keychain.

New validation regressions reproduced FAIL 20 / PASS 33: JSON arrays/ambiguous
object fields were accepted, malformed secret fields could be persisted, nested
handles were not refused before serialization, and malformed keyring references
were accepted. The store now validates those boundaries with typed errors that
do not include values. Existing Unix credential files are restricted to 0600
before atomic replacement preserves their mode. Current green: FAIL 0 / WARN 0 /
SKIP 1 / PASS 54.

Independent review found partial matching of external JSON/keyring field names
and treating unknown process liveness as proof of a stale lock. Regressions
reproduced FAIL 4 / PASS 56. Those record fields now use exact lookup, and an
access failure keeps a fresh lock held until its stale timeout unless the process
is positively known to be gone. The metadata test mocks keyring lookup and
asserts it is never called. Current green: FAIL 0 / WARN 0 / SKIP 1 / PASS 60.
Independent review cleared Task 8. Source and mirrored tests have zero scoped
lints for Tasks 7 and 8. No placeholder production dependencies are used.
The final combined 263-assertion run above includes the real vault, loader and
store together after documentation generation. Task 8 is ready for its scoped
source/test/evidence commit; no additional exports or dependencies are added.
