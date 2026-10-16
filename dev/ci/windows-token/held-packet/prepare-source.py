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
copy('baseline/helper-proc-writer-runtime.R', 'baseline/ordinary-helper-proc-writer-runtime.R')

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
postcondition_leaf = r'''# Fixed labels observe each original postcondition once without changing its result.
rw_absence_postcondition = function(key, value, phase) {
  keys = c("owner-marker", "existing-file", "denied-file", "missing-target", "dangling-entry",
    "existing-directory", "fresh-entries", "remove-owner", "remove-existing-file",
    "remove-denied-file", "remove-utilities", "remove-fresh-directory",
    "remove-existing-directory")
  if (!is.character(key) || length(key) != 1L || is.na(key) || !key %in% keys) {
    stop("Invalid absence postcondition diagnostic.")
  }
  emit = function(status) {
    tryCatch(phase(paste0("absence-post-", key, "-", status)),
      error = function(error) NULL, interrupt = function(error) NULL)
    invisible(NULL)
  }
  result = tryCatch(force(value), error = function(error) {
    emit("error")
    stop(error)
  }, interrupt = function(error) {
    emit("interrupt")
    stop(error)
  })
  emit(if (isTRUE(result)) "1" else "0")
  result
}
'''
postconditions_before = r'''  stopifnot(identical(readBin(owner, "raw", n = 27L), charToRaw(marker)),
    identical(bytes(paths[["file"]]), sentinel), identical(bytes(paths[["denied"]]), sentinel),
    !file.exists(paths[["missing"]]),
    !(basename(paths[["link"]]) %in% list.files(root, all.files = TRUE, no.. = TRUE)),
    !length(list.files(paths[["directory"]], all.files = TRUE, no.. = TRUE)),
    identical(sort(list.files(paths[["fresh"]], all.files = TRUE, no.. = TRUE)),
      sort(c("owner", "denied-file"))))
  stopifnot(file.remove(owner), file.remove(paths[["file"]]), file.remove(paths[["denied"]]),
    all(file.remove(paths[c("script", "recovery", "parent_backup", "file_backup", "armed",
      "token_source", "token_library", "token_compile")])),
    identical(unlink(paths[["fresh"]], recursive = FALSE), 0L),
    identical(unlink(paths[["directory"]], recursive = FALSE), 0L))'''
postconditions_after = r'''  post = function(key, value) rw_absence_postcondition(key, value, phase)
  stopifnot(post("owner-marker", identical(readBin(owner, "raw", n = 27L), charToRaw(marker))),
    post("existing-file", identical(bytes(paths[["file"]]), sentinel)),
    post("denied-file", identical(bytes(paths[["denied"]]), sentinel)),
    post("missing-target", !file.exists(paths[["missing"]])),
    post("dangling-entry",
      !(basename(paths[["link"]]) %in% list.files(root, all.files = TRUE, no.. = TRUE))),
    post("existing-directory",
      !length(list.files(paths[["directory"]], all.files = TRUE, no.. = TRUE))),
    post("fresh-entries", identical(sort(list.files(paths[["fresh"]], all.files = TRUE,
      no.. = TRUE)), sort(c("owner", "denied-file")))))
  stopifnot(post("remove-owner", file.remove(owner)),
    post("remove-existing-file", file.remove(paths[["file"]])),
    post("remove-denied-file", file.remove(paths[["denied"]])),
    post("remove-utilities",
      all(file.remove(paths[c("script", "recovery", "parent_backup", "file_backup", "armed",
        "token_source", "token_library", "token_compile")]))),
    post("remove-fresh-directory", identical(unlink(paths[["fresh"]], recursive = FALSE), 0L)),
    post("remove-existing-directory",
      identical(unlink(paths[["directory"]], recursive = FALSE), 0L)))'''
held_start = amended.index('rw_held_token_case = function')
amended = amended[:held_start] + postcondition_leaf + '\n' + amended[held_start:]
assert amended.count(postconditions_before) == 1
amended = amended.replace(postconditions_before, postconditions_after)
decoder_before = '    "rw_absence_observation", "rw_absence_privilege", "token_held_line", "token_held_decode")'
decoder_after = '    "rw_absence_observation", "rw_absence_privilege", "token_held_line", "token_held_decode",\n    "rw_absence_postcondition")'
assert amended.count(decoder_before) == 1
amended = amended.replace(decoder_before, decoder_after)
# Strict owned empty cleanup successor; the ordinary prefix remains byte-exact.
held_start = amended.index('rw_held_token_case = function')
head, held = amended[:held_start], amended[held_start:]
present_end = '  present = function(path) {\n    basename(path) %in% list.files(dirname(path), all.files = TRUE, no.. = TRUE)\n  }\n'
empty_cleanup = '  remove_empty = function(path, .witness = NULL) {\n    withCallingHandlers({\n      if (!is.character(path) || length(path) != 1L || is.na(path) ||\n          !(path %in% paths[c("fresh", "directory")])) {\n        return(FALSE)\n      }\n      key = if (identical(path, paths[["fresh"]])) "fresh" else "directory"\n      record = function(stage, bits) {\n        if (!is.null(.witness)) {\n          stopifnot(is.function(.witness))\n          .witness(paste0("absence-cleanup-", key, "-", stage, "-",\n            paste(as.integer(bits), collapse = "-")))\n        }\n      }\n      parent = list.files(root, all.files = TRUE, no.. = FALSE)\n      parent_ok = all(c(".", "..", basename(path)) %in% parent)\n      exists = dir.exists(path)\n      empty = identical(sort(list.files(path, all.files = TRUE, no.. = FALSE)), c(".", ".."))\n      record("before", c(identical(dirname(path), root), parent_ok, exists, empty))\n      if (!parent_ok || !exists || !empty) return(FALSE)\n      canonical = c(root = normalizePath(root, winslash = "/", mustWork = TRUE),\n        path = normalizePath(path, winslash = "/", mustWork = TRUE),\n        parent = normalizePath(dirname(path), winslash = "/", mustWork = TRUE))\n      parent_match = identical(canonical[["parent"]], canonical[["root"]])\n      path_match = identical(canonical[["path"]],\n        file.path(canonical[["root"]], basename(path)))\n      record("canonical", c(parent_match, path_match))\n      if (!parent_match || !path_match) return(FALSE)\n      status = unlink(canonical[["path"]], recursive = TRUE, force = FALSE, expand = FALSE)\n      after = list.files(canonical[["root"]], all.files = TRUE, no.. = FALSE)\n      parent_known = all(c(".", "..") %in% after)\n      removed = !(basename(path) %in% after)\n      record("after", c(status, parent_known, removed))\n      identical(status, 0L) && parent_known && removed\n    }, warning = function(w) stop(w))\n  }\n'
assert held.count(present_end) == 1
held = held.replace(present_end, present_end + empty_cleanup)
cleanup_before = '    if (dir.exists(paths[["fresh"]]) &&\n        !length(list.files(paths[["fresh"]], all.files = TRUE, no.. = TRUE)))\n      unlink(paths[["fresh"]], recursive = FALSE)\n    if (dir.exists(paths[["directory"]]) &&\n        !length(list.files(paths[["directory"]], all.files = TRUE, no.. = TRUE)))\n      unlink(paths[["directory"]], recursive = FALSE)'
cleanup_after = '    for (path in paths[c("fresh", "directory")]) {\n      if (present(path)) invisible(remove_empty(path, .witness = phase))\n    }'
assert held.count(cleanup_before) == 1
held = held.replace(cleanup_before, cleanup_after)
held = held.replace('post("remove-fresh-directory", identical(unlink(paths[["fresh"]], recursive = FALSE), 0L))',
    'post("remove-fresh-directory", remove_empty(paths[["fresh"]], .witness = phase))')
held = held.replace('post("remove-existing-directory",\n      identical(unlink(paths[["directory"]], recursive = FALSE), 0L))',
    'post("remove-existing-directory", remove_empty(paths[["directory"]], .witness = phase))')
amended = head + held
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
proof = {'unchanged_ordinary_prefix_bytes': len((packet / 'baseline/helper-proc-writer-runtime.R').read_bytes()),
         'copied_delimited_prefix_bytes': len(prefix.encode()),
         'ordinary_prefix_file': 'baseline/ordinary-helper-proc-writer-runtime.R',
         'ordinary_prefix_sha256': '56a0abb8eb595fbd103c8f423c4b5dba9438a5644c3dce19126ff1d70915f482',
         'ordinary_prefix_retained_source': 'source/dev/ci/windows-token/packet/baseline/helper-proc-writer-runtime.R',
         'experimental_baseline_file': 'baseline/helper-proc-writer-runtime.R',
         'experimental_baseline_bytes': 91738,
         'original_six_control_lines': control_lines,
         'strict_control_values': 'all six equal1', 'production_probe': 'PROBE1 unchanged',
         'old_aba_removed_only_from_successor': True,
         'baseline_native_source': '02ceac9c4a662cffe16188a592f7bdd3e2555280',
         'postcondition_keys': 13,
         'postcondition_leaf_source': 'c37550e35c9d8d9c723a3d27656183f5adfd8b552e37641afd512984856d89aa',
         'postcondition_predicates_and_order_unchanged': True,
         'execution': False}
(root / 'source-proof.json').write_text(json.dumps(proof, indent=2) + '\n')
print('prepared source successor; no parsing or execution')
