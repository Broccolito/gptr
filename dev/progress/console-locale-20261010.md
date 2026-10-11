# Thinking indicator in non-UTF-8 consoles (2026-10-10)

The hosted Linux C-locale job exposed an actual width failure: the Unicode label and
spinner frame expanded into native `<U+...>` text after fitting. A first native conversion
repair still overflowed because `cli::ansi_strtrim()` inserted an unrepresentable ellipsis.
Both failures are retained in the ignored validation evidence.

The spinner now uses ASCII frames and an ASCII ellipsis when the native locale is not
UTF-8, converts the label before fitting, and keeps the existing UTF-8 styling. Every
redraw reserves the last console column and pads the current row to erase shorter frames.
The wide-character assertion retains its exact display-width check in both locales.

Validation on the edited source:

- C-locale focused: 25 assertions, zero failures/warnings/skips.
- C-locale affected console packet: 204 assertions, zero failures/warnings, two explicit
  skips (UTF-8-only display widths and the CI-driven interactive interrupt).
- UTF-8 affected packet: 208 assertions, zero failures/warnings, one CI-only interrupt skip.
- Package-context lint: zero lints in both edited files. An initial standalone lint without
  loading the package reported undefined internal symbols; that diagnostic is retained.
- Independent PR-review lane found no blocker in the source or assertions.

The local testthat installation emits its separately retained R-build-version advisory.
These source-level checks do not claim the latest normal archive or hosted matrix is green;
those gates must run again after the compaction and document-write repairs are committed.
Evidence: `dev/.validation/spinner-locale-20261010/` (ignored).
