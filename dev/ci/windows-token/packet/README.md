# Child-only token experiment: prepared, unexecuted

This ignored packet is an executable diagnostic proposal, not a package/runtime change.
It preserves the full retained 02031 helper as a byte-identical prefix and appends a
private experimental case. No token, compiler, R child or native utility was run here.
The prior design-only packet remains separate. No CI, source or registry is changed.

The observed three enabled privileges and ineffective denial were correlated only.
This experiment compares the same `File.GetAttributes`, directory listing and generated
production absence probe on the same disposable Deny inputs: original token (A1), only
the Backup/Restore/ChangeNotify group disabled (B), original token restored (A2). It can
identify a contribution of this group on one runner, not an individual privilege or a
shipping bug. B=2 rejects this group hypothesis. Unknowns fail rather than count as denial.

## Exact native boundary

`current-token.cs` exposes no PID, external handle or privilege-name parameter. Its
constructor rejects a thread impersonation token, opens only the current-process token
with QUERY|ADJUST_PRIVILEGES and verifies its primary type. Full private snapshots are
bounded to 256 distinct LUIDs/64KiB and never printed. Only three existing enabled bits
are changed; DisableAllPrivileges and REMOVED are never used. Unrelated entries, order
and attributes must remain identical under full readback. The disabling NewState uses
documented zero attributes; original snapshot flags are not passed through as disable input.

Restoration is armed before adjustment. BOOL success plus immediate native error zero
and exact PreviousState are required. Verified PreviousState is retained; the separately
saved original target states also cover partial adjustment or invalid returned state.
Restore requires full original readback, including a second independent call in finally.
The token handle is closed exactly once after that attempt. A primary failure is retained
and rethrown after cleanup; fixed restoration/close failure tokens remain fatal. A killed
utility ends its own process token; it cannot alter a parent token. There is no whole-R
hard-kill ACL recovery claim.

The PowerShell fragment performs no additional DACL mutation. Owner plus complete ordered
Access/Owner SDDL and control flags must stay exact across A-B-A; original attributes and
entry membership are compared whenever lookup succeeds. The A1 baseline admits only the
previously observed readable metadata/listing input. No pre-opened file handle is used to
bypass the same lookup. All original protected creation, private descriptor backup,
arming, exact Deny rules, six control values, strict PROBE1, ACL restore and recovery code
are preserved. The intervention executes before the original strict lookup checks.

## Compilation, clocks and ownership

A separately owned PowerShell child compiles the fixed source to an ephemeral DLL before
the measured utility. It runs ten actual pure snapshot/boundary checks that use no token
or native API. Its soft operation bound is 30 seconds and it must have exact registered
PID/create-time identity, confirmed death and marker/record settlement before reuse.
The source is bounded and SHA-verified in R; the generated DLL is admitted at <=1MiB and
SHA-verified again in the measured utility before loading. No DLL or compiled code enters
package files, Imports, source, normal tests or a public installation.

The measured utility and independent ACL recovery each keep their original five-second
bound. Compilation is outside those clocks but inside the unchanged 30-second case,
45-second active watchdog plus 15-second settlement/60-second total, 1GiB combined
supervising-R/owned-family RSS and 64MiB disk/output bounds. These are concurrent caps:
compilation consuming the case budget fails; it does not earn extra measurement time.
The existing nofollow observer is mandatory, initialized once within its unchanged bounds.
No per-poll process, parent environment setter, source monkeypatch or warning suppression
is introduced. Unexpected utility stderr or parser errors latch failure even though
reactor callbacks themselves return diagnostics. Unknown settlement still blocks recovery
and deletion. Source checks do not establish actual startup, compilation or token parity.

## Evidence and acceptance

The live utility emits exactly 26 closed fixed numeric token records; it cannot assert
its own settlement. The existing R executor independently proves compiler/utility death.
Native handles, names, SIDs, raw descriptors, token contents and raw errors are never emitted.
Fixed millisecond timing and compiler PID/create-time observations are retained separately.
The decoder refuses missing, duplicate, out-of-order, unknown, ineffective or un-restored
records. A group contribution requires all three lookups A1=2/B=1/A2=2 plus exact token
and Access checks. Other valid outcomes record no group contribution.

Seven pure protocol controls and one Windows native test are prepared, unrun and unregistered.
The native test retains `expect_true(x$complete)` from the original feature acceptance.
Thus an instrumentally complete A-B-A with original PROBE2 is still a failed feature test.
Neither `feature_accepted=FALSE` nor a diagnostic success is a waiver. Root must keep the
original selected native case and all security controls mandatory in its normal run.

## Nomination, after independent review

Root owns provisioning, current source/certificate admission, environment construction,
the hosted lease and raw result gate. Nominate only a fresh Windows Rscript child with
the existing complete helper environment, explicit private Python and managed=false,
`GPTR_OPTIONAL_NOFOLLOW_OBSERVER=true`, live=false, and `GPTR_TOKEN_EXPERIMENT_PACKET`
set to this copied ignored packet. Caller token/environment is never adjusted. Load the
exact certified installed package (or separately identified source context) before tests.
Require all seven pure controls first, no warnings/skips/raw conditions/zero assertions.
Then run the one native test and retain its complete raw results even when RED.

The existing testthat API can execute the prepared files in a private scope:

```r
packet = Sys.getenv("GPTR_TOKEN_EXPERIMENT_PACKET")
scope = new.env(parent = asNamespace("testthat"))
sys.source(file.path(packet, "token-protocol.R"), envir = scope)
testthat::test_file(file.path(packet, "controls", "test-token-protocol.R"), env = scope)
testthat::test_file(file.path(packet, "controls", "test-token-native.R"), env = scope)
```

These calls are a nomination recipe, not an outer timeout or successful exit gate. Reuse
the coordinator's owned 300-second file supervisor and raw condition/result gate; do not
turn a returned testthat result into an automatic pass. The embedded bp watchdog retains
its existing tighter clocks, RSS, entry and byte limits. No dispatch is authorized here.

## Primary API support

[AdjustTokenPrivileges](https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-adjusttokenprivileges)
requires checking the immediate error and supports restoring captured PreviousState;
privilege removal is irreversible and excluded.
[OpenProcessToken](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-openprocesstoken),
[GetTokenInformation](https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-gettokeninformation),
[LookupPrivilegeValueW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-lookupprivilegevaluew)
and [TOKEN_PRIVILEGES](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-token_privileges)
support the fixed system-DLL boundary. PowerShell 5.1 Add-Type compilation and all native
ABI/latency/readback claims remain actual prerequisite gates, not source-proven results.
