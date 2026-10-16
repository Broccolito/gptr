import difflib
import hashlib
import json
from pathlib import Path

root = Path(__file__).parent
retained = root.parent / 'current-windows-security-02ceac9-38290862852-triage'
packet = retained / 'source/dev/ci/windows-token/packet'

def copy(name, target=None):
    target = root / (target or name)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes((packet / name).read_bytes())

for name in ['current-token.cs', 'baseline/helper-proc-backpressure.R',
             'baseline/helper-bp-disk-observer.R', 'baseline/fixtures/bp-disk-observer.py']:
    copy(name)
copy('amended/helper-proc-writer-runtime.R', 'baseline/helper-proc-writer-runtime.R')
copy('controls/test-token-native.R', 'baseline/test-token-native.R')
copy('token-protocol.R', 'baseline/token-protocol.R')
copy('token-trial.ps1', 'baseline/token-trial.ps1')
copy('manifest.json', 'baseline/owner-manifest.json')

original = (root / 'baseline/helper-proc-writer-runtime.R').read_text()
prefix = original[:original.index('rw_token_case = function')]
amended = original[len(prefix):]

def replace(old, new):
    global amended
    assert amended.count(old) == 1, old
    amended = amended.replace(old, new, 1)

replace('rw_token_case = function(case, root)', 'rw_held_token_case = function(case, root)')
replace('rw_token_run = function(packet)', 'rw_held_token_run = function(packet)')
replace('scope$bp_child_case = rw_token_case', 'scope$bp_child_case = rw_held_token_case')
replace('envir = environment(rw_token_run)', 'envir = environment(rw_held_token_run)')
replace('runner("native-token-experiment",', 'runner("native-held-token",')
replace('"$tokenProductionProbe = {", fun("proc_writer_acl")(paths[["denied"]], marker), "}",\n'
        '    strsplit(token_fragment, "\\n", fixed = TRUE)[[1L]])',
        '"# Admitted current-process token assembly is now loaded.")')
# Definitions precede the outer try. Only the factory opens a token inside the window.
replace('    observations,\n    "[Console]::WriteLine(\'GPTR_ABSENCE_STAGE 1\')",',
        '    strsplit(token_fragment, "\\n", fixed = TRUE)[[1L]],\n'
        '    observations,\n    "[Console]::WriteLine(\'GPTR_ABSENCE_STAGE 1\')",')
replace('    "ObservePrivileges \'PRE\'",\n'
        '    "$parentOriginal = StableOwnedAccess $false",\n'
        '    "$fileOriginal = StableOwnedAccess $true",',
        '    "$parentOriginal = StableOwnedAccess $false",\n'
        '    "$fileOriginal = StableOwnedAccess $true", trial,\n'
        '    "InvokeHeldToken {",\n    "ObservePrivileges \'PRE\'",')
replace('    "ObservePrivileges \'LOOKUP\'", trial,',
        '    "ObservePrivileges \'LOOKUP\'",')
replace('    "[Console]::WriteLine(\'GPTR_ABSENCE_STAGE 9\')",\n    "} finally {",',
        '    "[Console]::WriteLine(\'GPTR_ABSENCE_STAGE 9\')",\n'
        '    "}",\n    "} finally {",')
old = '''      if (startsWith(line, "GPTR_TOKEN")) {
        stopifnot(identity, identical(seen$last_stage, 7L))
        token = token_trial_line(line, seen$token_keys)
        stopifnot(is.list(token))
        seen$token_keys = c(seen$token_keys, token$key)
        seen$tokens = c(seen$tokens, line)
        phase(line)
        if (length(seen$tokens) == 26L) {
          diagnostic = token_trial_decode(seen$tokens)
          phase(paste0("token-group-contribution-", as.integer(diagnostic$group_contribution)))
          phase("token-feature-accepted-0")
        }
        return(invisible(NULL))
      }'''
new = '''      if (startsWith(line, "GPTR_HELD")) {
        stopifnot(identity)
        token = token_held_line(line, seen$token_keys)
        stopifnot(is.list(token), identical(seen$last_stage,
          if (startsWith(token$key, "B ")) 4L else 9L))
        seen$token_keys = c(seen$token_keys, token$key)
        seen$tokens = c(seen$tokens, line)
        phase(line)
        return(invisible(NULL))
      }'''
replace(old, new)
replace('''      if (!is.null(control)) {
        stopifnot(identity, identical(seen$last_stage,''',
        '''      if (!is.null(control)) {
        stopifnot(identical(seen$token_keys,
          c("B BACKUP", "B RESTORE", "B CHANGE_NOTIFY", "B TOKEN_EXACT")))
        stopifnot(identity, identical(seen$last_stage,''')
replace('''      if (!is.null(privilege)) {
        stopifnot(identity, identical(seen$last_stage,''',
        '''      if (!is.null(privilege)) {
        stopifnot(identical(privilege$value, 1L), identical(seen$token_keys,
          c("B BACKUP", "B RESTORE", "B CHANGE_NOTIFY", "B TOKEN_EXACT")))
        stopifnot(identity, identical(seen$last_stage,''')
replace('stopifnot(length(seen$tokens) == 26L, is.list(token_trial_decode(seen$tokens)))',
        'stopifnot(length(seen$tokens) == 7L, is.list(token_held_decode(seen$tokens)))')
fragment_hash = hashlib.sha256((root / 'token-held.ps1').read_bytes()).hexdigest()
replace('bounded_source("token-trial.ps1", 8192L,\n'
        '    "aae0e9b54331f8dc3a94bc2e8fe49d734bbc74345dbfb69ac803e4d28142e2c6")',
        'bounded_source("token-held.ps1", 8192L,\n    "' + fragment_hash + '")')
replace('"rw_absence_observation", "rw_absence_privilege", "token_trial_line", "token_trial_decode")',
        '"rw_absence_observation", "rw_absence_privilege", "token_held_line", "token_held_decode")')
target = root / 'amended/helper-proc-writer-runtime.R'
target.parent.mkdir(parents=True, exist_ok=True)
amended = prefix + amended
target.write_text(amended)
assert amended.startswith(prefix)
# Every original six-control statement and strict probe requirement remains in order.
controls = ['PRE_FILE', 'PRE_PARENT', 'FILE_ACL', 'PARENT_ACL', 'FILE_LOOKUP', 'PARENT_LOOKUP']
start = original.index('rw_token_case = function')
baseline_lines = original[start:].splitlines()
control_lines = [line for line in baseline_lines if 'GPTR_ABSENCE_CONTROL ' in line]
assert len(control_lines) == 6
positions = [amended.index(line, len(prefix)) for line in control_lines]
assert positions == sorted(positions)
assert all(amended.count(line) == original.count(line) for line in control_lines)
assert 'identical(seen$control_values, rep(1L, 6L))' in amended
assert 'identical(seen$probe, "absence-probe-1")' in amended

native = (root / 'baseline/test-token-native.R').read_text()
native = native.replace('owned-token A-B-A retains the strict native absence oracle',
                        'owned held-disabled token proves the strict native absence oracle')
native = native.replace('GPTR_TOKEN_EXPERIMENT_PACKET', 'GPTR_HELD_TOKEN_PACKET')
native = native.replace('"token-protocol.R"', '"token-held-protocol.R"')
native = native.replace('scope$rw_token_run(packet)', 'scope$rw_held_token_run(packet)')
first = native.index('  tokens = x$phases[')
last = native.index('  # This remains the original positive feature requirement;', first)
native = native[:first] + '''  tokens = x$phases[startsWith(x$phases, "GPTR_HELD ")]
  expect_length(tokens, 7L)
  if (length(tokens) == 7L) {
    diagnostic = scope$token_held_decode(tokens)
    expect_true(diagnostic$disabled_exact)
    expect_true(diagnostic$body_finished)
    expect_true(diagnostic$restored_exact)
    expect_true(diagnostic$handle_closed)
    expect_false(diagnostic$individual_privilege_identified)
    expect_false(diagnostic$restored_privilege_denial_proved)
  }
''' + native[last:]
(root / 'controls/test-held-native.R').write_text(native)

changes = [('baseline/helper-proc-writer-runtime.R', 'amended/helper-proc-writer-runtime.R'),
           ('baseline/test-token-native.R', 'controls/test-held-native.R')]
patch = ''
for before, after in changes:
    patch += ''.join(difflib.unified_diff((root / before).read_text().splitlines(True),
        (root / after).read_text().splitlines(True), fromfile=before, tofile=after))
(root / 'held-successor.patch').write_text(patch)
proof = {'unchanged_ordinary_prefix_bytes': len(prefix.encode()),
         'original_six_control_lines': control_lines,
         'strict_control_values': 'all six equal1', 'production_probe': 'PROBE1 unchanged',
         'old_aba_removed_only_from_successor': True,
         'baseline_native_source': '02ceac9c4a662cffe16188a592f7bdd3e2555280',
         'execution': False}
(root / 'source-proof.json').write_text(json.dumps(proof, indent=2) + '\n')
print('prepared source successor; no parsing or execution')
