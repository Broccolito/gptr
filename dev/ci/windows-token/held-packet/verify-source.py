import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).parent
retained = root.parent / 'current-windows-security-02ceac9-38290862852-triage'
source = retained / 'source/dev/ci/windows-token/packet'

# Apply every exact unified hunk forward and backward without invoking project code.
patch = (root / 'held-successor.patch').read_text().splitlines(True)
index = 0
verified = []
while index < len(patch):
    assert patch[index].startswith('--- ')
    before = patch[index][4:].strip()
    index += 1
    assert patch[index].startswith('+++ ')
    after = patch[index][4:].strip()
    index += 1
    old = (root / before).read_text().splitlines(True)
    new = (root / after).read_text().splitlines(True)
    result = []
    cursor = 0
    hunks = []
    while index < len(patch) and not patch[index].startswith('--- '):
        match = re.fullmatch(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@.*\n',
                             patch[index])
        assert match
        old_start, old_count, new_start, new_count = [
            int(value) if value is not None else 1 for value in match.groups()]
        index += 1
        deleted, inserted = [], []
        while index < len(patch) and not patch[index].startswith(('@@ ', '--- ')):
            line = patch[index]
            assert line[0] in ' +-'
            if line[0] in ' -':
                deleted.append(line[1:])
            if line[0] in ' +':
                inserted.append(line[1:])
            index += 1
        assert len(deleted) == old_count and len(inserted) == new_count
        position = old_start - 1
        assert old[position:position + old_count] == deleted
        result.extend(old[cursor:position])
        result.extend(inserted)
        cursor = position + old_count
        hunks.append((new_start - 1, inserted, deleted))
    result.extend(old[cursor:])
    assert result == new
    reverse = new[:]
    for position, inserted, deleted in reversed(hunks):
        assert reverse[position:position + len(inserted)] == inserted
        reverse[position:position + len(inserted)] = deleted
    assert reverse == old
    verified.append({'before': before, 'after': after, 'hunks': len(hunks)})

for name in ['current-token.cs', 'baseline/helper-proc-backpressure.R',
             'baseline/helper-bp-disk-observer.R', 'baseline/fixtures/bp-disk-observer.py']:
    assert (root / name).read_bytes() == (source / name).read_bytes()
ordinary = (source / 'baseline/helper-proc-writer-runtime.R').read_bytes()
assert (root / 'amended/helper-proc-writer-runtime.R').read_bytes().startswith(ordinary)
for name in ['token-held.ps1', 'token-held-protocol.R', 'controls/test-held-faults.ps1',
             'controls/test-held-protocol.R', 'controls/test-held-native.R']:
    data = (root / name).read_bytes()
    assert all(value < 128 for value in data)
    assert all(len(line) <= 100 and line == line.rstrip()
               for line in data.decode().splitlines())
helper = (root / 'amended/helper-proc-writer-runtime.R').read_text()
fragment_sha = hashlib.sha256((root / 'token-held.ps1').read_bytes()).hexdigest()
assert fragment_sha in helper
body_start = helper.index('    "InvokeHeldToken {",')
body_end = helper.index('    "}",\n    "} finally {",', body_start)
window = helper[body_start:body_end]
assert window.count('GPTR_ABSENCE_CONTROL ') == 6
assert 'fun("proc_writer_acl")(paths[["denied"]], marker)' in window
assert 'UnauthorizedAccessException' in window and 'GPTR_ABSENCE_PROBE 1' in window
assert 'Independent native denial not effective' in window
assert 'identical(seen$control_values, rep(1L, 6L))' in helper
assert 'identical(seen$probe, "absence-probe-1")' in helper
held_body = helper[helper.index('rw_held_token_case = function'):]
assert held_body.count('post("') == 13
assert 'rw_absence_postcondition = function(key, value, phase)' in helper
assert '"rw_absence_postcondition")' in held_body

proof = {'forward_and_inverse': verified, 'ordinary_helper_prefix_bytes': len(ordinary),
         'bridge_and_watchdog_copies_exact': True, 'controls_inside_window': 6,
         'actual_generated_production_probe_inside_window': True,
         'new_r_protocol_titles': 2, 'powershell_fault_cases': 12,
         'native_fixture_titles': 1, 'execution': False,
         'postcondition_keys': 13, 'postcondition_predicates_and_order_unchanged': False,
         'postcondition_keys_and_order_unchanged': True, 'canonical_cleanup_source_only': True}
(root / 'forward-inverse.json').write_text(json.dumps(proof, indent=2) + '\n')
files = {}
for path in sorted(root.rglob('*')):
    if path.is_file() and path != root / 'manifest.json':
        data = path.read_bytes()
        files[str(path.relative_to(root))] = {
            'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
baseline = {name: hashlib.sha256((retained / name).read_bytes()).hexdigest()
            for name in ['manifest.json', 'AUDIT.json', 'REPORT.md']}
manifest = {'source_sha': '02ceac9c4a662cffe16188a592f7bdd3e2555280',
            'baseline_actual_run': 38290862852, 'baseline_actual_job': 114950342213,
            'retained_baseline': str(retained), 'retained_baseline_sha256': baseline,
            'files': files, 'prepared_only': True, 'production_changed': False,
            'native_run': False, 'r_or_powershell_parsing_or_execution': False,
            'ordinary_fixture_adoption': False, 'restored_privilege_acceptance': False}
(root / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps({'manifest_sha256': hashlib.sha256((root / 'manifest.json').read_bytes()).hexdigest(),
                  'files': len(files), 'forward_inverse': len(verified)}))
