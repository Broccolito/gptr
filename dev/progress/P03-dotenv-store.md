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

## Pending

Task 7 waits for the real redactor. Its `secret_discover_env()` amendment is
coordinated with the owner of `auth-secrets.R`. Task 8 follows the same real
vault/redactor dependencies. No placeholder production functions are used.
