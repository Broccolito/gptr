## Submission

gptr 1.0.0 is a pure-R package. Examples and the 14 precomputed guides run offline without credentials. CRAN submission is being prepared.

License change: gptr 0.7.0 was released under `MIT + file LICENSE`; gptr 1.0.0 is released under `Apache License (== 2.0)`, with the agreement of its contributors. Third-party notices for derived MIT-licensed material are in `inst/COPYRIGHTS`.

## Test environments

- Local: macOS arm64, R 4.6.1, `R CMD check --as-cran --no-manual`.
- GitHub Actions: Ubuntu (devel, release, oldrel-1, oldrel-4, `LC_ALL=C`, no Suggests), macOS (release) and Windows (release, oldrel-4).

## R CMD check results

0 errors | 0 warnings | 0 notes on macOS (474.5 s; 30,643 test assertions, 446 skipped on CRAN or by platform).

Windows reports an installed-size NOTE (about 9.8 Mb).

## Installed size

The normal installation is 6,960,570 bytes, of which `R/gptr.rdb` is 5,046,495 bytes; the source archive is 2,635,034 bytes and documentation and data are each below 5 MB. The code is byte-compiled pure R. Disabling byte compilation halves the installed size but makes first calls about three times slower, so we kept it. We found no duplicated payload to remove without losing functionality, security checks or the offline guides, and ask for CRAN's consideration of the size.
