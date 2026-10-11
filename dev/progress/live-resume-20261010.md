# Resumed live and native validation, 2026-10-10

These are scoped observations, not completion of the living testing plan. Raw
evidence stays in ignored `dev/.validation/live-20261010/`. Keys loaded only
through the approved quiet `gptr_env()` bootstrap, never into documents/logs.
Original failed runs and unrelated user processes were preserved.

## Immutable installation checkpoints

Normal3d92b05 archive SHA256
`5ced56de6454cba771af7fff4a6459a22a5fb2258b351ee92ce678e0a9899d05` was actually installed,
with a separate successful14-guide/source certificate after the first verifier
incorrectly included the generated index page. Normal8952567 archive SHA256
`e22172a337fe8efd6383aa570675061aae193fc7b1c7bff5680490e85550c6a8` was installed subsequently:
14.19s, status0,14 guides and119 source-file fingerprints,15 resource samples,
421.5MiB peak family RSS and zero sampling errors. Existing observations retain
their actual revision. Hosted R4.6.1-produced tarballs have different digests;
download/verification alone is not local adoption or execution.

## True4GiB loaded-object execution

The fresh3d92b05 Rscript materialized536,870,912 ordinary doubles in a private,
locked binding:4,294,967,296 data bytes, allocated in0.420s. Three successive real
Azure iterations each used exactly one guarded read-only builtin R expression on
the same object. Length/sum, mean/endpoints and range/samples matched independent
full-scan oracles. Pointer/tracemem identity and the input remained unchanged.

Controller elapsed17.261s; request/tool rounds5.036/3.548/3.801s; tool execution
0.725/0.596/0.553s; separately measured oracle scans1.189/1.199/1.186s. Six real
requests had512-token response caps and7,483–14,785-byte bodies; no data payload
was serialized into the requests. Explicit cache hints/store were disabled;
reported provider implicit cache use was preserved rather than assumed absent.

Sampled family peak4,287.75MiB versus153.2MiB baseline,17 samples/zero errors;
no tracemem duplication line. Owned retained file peak27,290bytes/largest24,412;
output375bytes. Input removal and GC returned measured RSS to191.7MiB. All12
restoration/settlement witnesses were true, with no warnings, timeout or guard
stop. Process exit released remaining heap. This proves the three synthetic
read-only operations, not universal zero-copy, every temporary allocation or
every OS write. Evidence: `runs/versa-four-gib-3d92b05/`.

## Source/decision/steering workflows

| Revision/case | Actual outcome |
|---|---|
|3d Azure emulated S1|Live5.661s with3 decision usage rows; same-process cache hit had0 fresh rows/requests, fresh-child replay0.327s had0 calls/rows/key reads. Provenance explicitly emulated/calibration unknown.|
|3d Azure teams/fan-out|Live9.555s with10 real requests and2 recorded blocks; fresh replay0.410s with0 calls/usage. Live child mean/median oracles and replay reports/provenance passed; unexported child numeric values were not claimed persisted.|
|3d native Jev direct Rscript|Actual vanilla child live0.996s/3 typed blocks/3 native rows; fresh child replay0.576s/0 calls/native rows with unchanged source fingerprint.|
|895 Azure steering|Corrected active-session/background-pump fixture8.693s/6 requests+usage, both values19.2 and idle, background running when steered;223.2MiB peak/10 samples/0 errors. Original initial-prompt-starvation failures retained.|
|895 Azure simulation|Protected seeded1000-by20 simulation4.720s/2 requests+usage; coverage0.952/average_mean−0.005778123 matched an independent oracle, integer bindings remained locked and caller RNG unchanged;174.0MiB peak/6 samples/0 errors. Original input-type failure retained.|

The steering correction is in the ignored test fixture. A canonical request spy
proved that a prestart steer reached the model ahead of the queued initial
prompt/context. Starting one bounded initial turn before steering delivered the
intended instructions and attached objects; no runtime queue change or raised
budget was needed. Neither steering case proves native GUI typing/idle pumping.

## Native clients

VS Code3d used the actual attached vanilla R process and official R extension.
The active delayed-provider probe observed host widths73→92→37 during text and
two real R tools, with readable prose/fence/table/result separation, exact numeric
oracles and all eight cleanup witnesses. R's width option stayed80 while the
host CLI width changed. New output adapts; old scrollback reflow belongs to the
client. Probe49.79s; attached150s profile peak241.4MiB/0 sampling errors.

VS Code3d provider live/same-process fresh-namespace replay passed Azure
3.258/0.171s, Jev0.462/0.058s, Codex9.320/0.236s and exactQwen18.703/0.192s.
Replay made zero fresh requests/usage/native rows. A300s attachment profile
sampled897.9MiB family peak, including CLI descendants and idle time; it is not
per-provider latency/RSS. Claude reported its actual quota reset18:00PDT; that
failure and complete restoration were retained, and later cells ran separately.

RStudio3d active probe50.169s observed native widths199/122 during inference and
two tools, independent values and all eight restoration witnesses. R.app3d
probe50.069s passed computation/layout/cleanup, but the automation action waited
through execution; widths stayed79 and active resize was not reached. R.app's
100s attachment peak253.4MiB/zero sample errors is a scoped static observation.

RStudio895 numeric/recording/live and same-process replay passed Azure
3.592/0.177s, Jev0.458/0.061s and Codex8.622/0.172s. Codex's notice appeared as a
separate paragraph, providing installed native evidence for the notice fix.
Replay accounting and RNG/frontend cleanup passed. A90s attachment profile
sampled828.6MiB/0 errors. These runs also emitted at least50 identical warnings:
registered-secret-redacted diagnostic `internal error 1 in R_decompress1 with
libdeflate`. They are not classified clean. Stale lazy-loaded data after changing
the shared validation install in a long-lived R process is a hypothesis; fresh
session reproduction is pending. A stale computer-use window error was resolved
by rebinding/raising the same existing window; PID32778 remained alive, so it
does not establish an RStudio crash. No user document was changed by the
diagnostic. The source editor and console focus were checked before proceeding.

## Headless notebook boundary

The895 serial IRkernel lane reports successful fresh-kernel live/replay for
Azure and Codex regression/teams, Jev typed and exactQwen regression, with
independent values, recording/source fingerprints, zero replay provider rows and
explicit RNG/frontend cleanup. Its detailed current certificate belongs in the
client ledger; these are computational, not active notebook GUI observations.
ExactQwen serialized teams reached the eight-turn budget and exposed a menu in
an explicitly interactive headless fixture. The owned controller/family was
stopped without extending the budget; no replay/pass is inferred. Its retained
trajectory and nonblocking headless stop guard require review.

## Resource and ongoing boundaries

Before the4GiB job the host had64.35%CPU idle/33GiB unused; swap42,415.94MiB and
13GiB free disk remained constraints. Qwen's external server reported17.945GiB
resident model/VRAM and context metadata262144, separate from sub-GiB R-family
measurements. Natural keep-alive expiry, without an unload/kill, returned wired
memory near7GiB and unused memory near27GiB in the earlier observation. Context
metadata does not prove a full-context inference or allocation breakdown.

No additional GPU/high-memory case runs without a fresh resource decision.
Compaction, storage safety/deltas, realistic extension/file/network workflows,
remaining native controls, Claude after reset, system-wide/native-local decision
routing and hosted final-platform gates remain explicit ongoing/waiting cases.
No release, public deployment or CRAN submission was performed.

The mandatory cross-plan sequence after the added storage/compaction plan exited
0 at all four stages (index/extract/parse/lint). The first sandboxed attempt was
retained: OpenMP shared-memory initialization was denied before the analyzer ran;
the authorized rerun used one BLAS/lint worker. Existing numbered-plan warning
categories remain distinct from zero new parse/style/lint errors.
