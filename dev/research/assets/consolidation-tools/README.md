# Plan consistency tools

These tools checked the 25 implementation plans for cross-plan consistency and ran the final gate on
2026-10-01. Re-run them after editing any plan, so a change in one plan does not silently break another.

| Tool | What it does |
|---|---|
| `build_index.py` | Parses every `dev/plan/P*.md`. It indexes every function defined and called (with argument names), every file each task touches, and every option, condition, event, registry kind, service and test helper. It then reports error/warn/info findings: duplicate definitions, files created by two plans, undefined calls, argument names that are not formals of the callee, calls outside a plan's dependency closure, undefined test helpers, and near-identical names. Output goes to a new temporary directory, whose path it prints. |
| `extract.py` | Writes every fenced code block of P01-P25 to `./blocks/` (`<plan>_L<fence line>_<lang>_d<nesting>.txt`). |
| `check_r.R` | Checks that every R block in `./blocks/` parses and has no `<-`, `->`, `%>%` or non-ASCII byte. |
| `lint_all.R` | Lints a directory of `.R` files with P01's `.lintr` linters (`indentation_linter = NULL`). |

The full check, run from the repository root:

```bash
T="$PWD/dev/research/assets/consolidation-tools"
python3 "$T/build_index.py" --quiet
cd "$(mktemp -d)" && python3 "$T/extract.py"
Rscript --vanilla "$T/check_r.R"
mkdir lint && for f in blocks/*_r_d0.txt; do cp "$f" "lint/$(basename "$f" _r_d0.txt).R"; done
Rscript --vanilla "$T/lint_all.R" lint
```

Expected: `25 plans, 1440 blocks, ... findings (info 812, warn 74)` with no `error` findings; `764 R blocks; 0 with
parse/style problems` (one `LONG` note for an example inside a P17 skill markdown file); `no lints`.

State at the final gate: 25 plans, 307 tasks, 1,517 code blocks, 740 top-level R blocks, 0 error-level
findings, 0 parse errors, 0 `<-`, 0 `%>%`, 0 lints. The 74 remaining warnings are triaged in the plans'
"Cross-plan consolidation log" sections (recorded exceptions, call-shaped Interfaces lines, research-prototype
names in prose).

`build_index.py` and `extract.py` read the plans of the repository that holds them.
`consolidation-lint-results.csv` (one directory up) is the lint report that drove the last fixes.
