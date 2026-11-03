# On-demand discovery prompt cost

The R tool description now points to `peter$search()` and `peter$help()` in every preset.
The o200k static prefix measurements are 1304 (minimal), 2422 (standard core),
2900 (standard all), and 3043 (standard interactive): increases of 42, 87, 87,
and 87 tokens. The measured golden-transcript prefix/input totals and their
estimates were updated for this instruction only. Request counts, output totals,
images, catalog size, and retained facts are unchanged across all 14 fixtures.
The existing 2% prefix and 5% input/output regression tolerances are unchanged.

Measured with `Rscript --vanilla dev/bench/tokens/run.R --check` on the discovery,
plugin diagnostics, API documentation, and MCP wait candidate combined. The other
three changes do not alter the measured prompt. Runtime model identity context is
a separate change and must be measured through the actual request assembly path.
