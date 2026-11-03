# Runtime model identity prompt cost

The golden transcript runner now uses the actual `run_build()` seam. The compact
route/identity context is appended only when it changes, so the real request stays
append-only and repeated builds add no duplicate note. In these fixtures the
initial note costs 80 o200k tokens (75 estimated); route changes retain earlier
notes as historical entries. The smallest transcript initially exceeded the
unchanged 5% input gate (3052 to 3212 tokens).

Only measured input totals and their estimates were rebaselined across the 14
fixtures. Frozen prefixes, request counts, outputs, images, catalog tokens and
retained facts are unchanged. Regression tolerances remain unchanged.
