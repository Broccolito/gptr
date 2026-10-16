# Native callr environment handoff

Reviewed development patch against callr3.8.0, commit
`6a7dd7a51dbf16b3a28819264aa2db04c960399f`. It passes the final environment directly
to processx across all five launchers, preserving callr classes, serialization, hooks,
tracing, streams and lifecycle. No temporary caller environment setter is used.

This is a partial upstream candidate, not a globally installed or released dependency.
GPTR runtime, Imports and pure-R packaging remain unchanged. The patch is excluded
from R builds with the existing dev ignore rule. Actual outcomes belong in
[task progress](../../progress/skipped-platform-tests-20261010.md). Source review alone
does not prove execution.

## Reproduce

The on-demand `callr-native-environment` workflow requires a full source SHA; the
reviewed branch also runs it for changes to this packet and its dedicated fixtures.
It verifies all167 pinned source-file hashes, applies the exact patch, and verifies
the168 resulting files. It installs stock and patched callr in separate private
runner libraries, never a shared library. Each runs in a fresh R process.

The stock Windows original worker/artifact cases must reproduce exactly four failures
each; Linux must pass. The repaired six-case file must pass both hosts, with zero
warnings, fixture errors or skips. Nine upstream cases cover environment overlays,
extra environment precedence and all five launchers. Four admission cases retain
explicit startup-seed, child-restoration and essential PATH-removal results separately.
Their RED results cannot be reported as a universal child-environment pass.

After those core gates pass, four complete unchanged upstream files run separately on
stock and patched builds:20 cases for background lifecycle/errors/streams, hooks,
timeout, and tracing. Their raw warnings/errors/skips remain fatal. SDK recording is
in memory in fresh children with telemetry environment settings removed; actual test
dependency versions must match across all eight files. Five pure controller tests
ensure core failures prevent compatibility execution and incompatible dependencies
or failed assertions cannot count as a compatibility pass.

The existing fixture bounds remain30seconds per case,60seconds outer,1GiB family
RSS and64MiB owned output. The dedicated install/file controller additionally has
300seconds,2GiB total owned-family RSS,1MiB per evidence file, exact inherited-marker
cleanup and five-second settlement. Warnings remain fatal through publication; raw
error counts are checked before diagnostic truncation. No credentials or models are
used. At most two hosted jobs run; the local resource gate and shared Ollama are
preserved.

## Remaining admission boundaries

- R startup may normalize absent/empty library seeds on either OS before callr runs.
  Windows common_hook also cannot restore true-empty startup values through the
  current R CRT setter. Native requested seeds and prelaunch observations are distinct.
- Windows processx3.9 replenishes missing essential OS variables from its parent.
  Explicit PATH removal can therefore differ from callr's former temporary-unset path.
- Non-ASCII Windows variable-name folding needs separate native/locale proof.

Do not mutate dependency namespaces, add a Win32-only setter, write CRT vectors,
normalize caller empties, suppress equality failures or install a dependency fork
globally. Upstream publication and a compatible released dependency are required
before changing GPTR minimum versions or claiming production closure.
