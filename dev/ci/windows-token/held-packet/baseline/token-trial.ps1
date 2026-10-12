# Inserted after the existing exact Deny readbacks and LOOKUP observations.
# The enclosing script owns $fresh/$denied/$sections/$sid and the original ACL recovery.
$lease = $null
$primaryFailure = $null
$cleanupFailure = $null
$tokenRestored = $false
$tokenClosed = $false
$fileSecurity = [System.IO.File]::GetAccessControl($denied, $sections)
$fileDescriptor = $fileSecurity.GetSecurityDescriptorSddlForm($sections)
$parentSecurity = [System.IO.Directory]::GetAccessControl($fresh, $sections)
$parentDescriptor = $parentSecurity.GetSecurityDescriptorSddlForm($sections)
$fileAttributes = [System.IO.File]::GetAttributes($denied)
$parentAttributes = [System.IO.File]::GetAttributes($fresh)
$parentEntries = @([System.IO.Directory]::GetFileSystemEntries($fresh))
if ($parentEntries.Count -ne 2) { throw 'Token input membership' }

function AssertTokenInputs {
  $actualFile = [System.IO.File]::GetAccessControl($denied, $sections)
  $actualParent = [System.IO.Directory]::GetAccessControl($fresh, $sections)
  AssertDenied $actualFile 128 0
  AssertDenied $actualParent 1 3
  if ($actualFile.GetSecurityDescriptorSddlForm($sections) -cne $fileDescriptor -or
      $actualParent.GetSecurityDescriptorSddlForm($sections) -cne $parentDescriptor) {
    throw 'Token input Access changed'
  }
}
function ObserveTokenTrial([string]$phase, [bool]$disabled) {
  if (@('A1', 'B', 'A2') -cnotcontains $phase) { throw 'Token phase unknown' }
  AssertTokenInputs
  if ($disabled) { $lease.VerifyDisabled() } else { $lease.VerifyOriginal() }
  $codes = $lease.StateCodes()
  if ($codes.Length -ne 3) { throw 'Token states unknown' }
  $keys = @('BACKUP', 'RESTORE', 'CHANGE_NOTIFY')
  for ($i = 0; $i -lt 3; $i++) {
    [Console]::WriteLine('GPTR_TOKEN ' + $phase + ' ' + $keys[$i] + ' ' + $codes[$i])
  }
  $fileCode = 3
  try {
    $value = [System.IO.File]::GetAttributes($denied)
    if ($value -ne $fileAttributes) { throw 'Token file attributes changed' }
    $fileCode = 2
  } catch [System.UnauthorizedAccessException] { $fileCode = 1 }
  [Console]::WriteLine('GPTR_TOKEN ' + $phase + ' FILE_LOOKUP ' + $fileCode)
  $parentCode = 3
  try {
    $value = [System.IO.File]::GetAttributes($fresh)
    if ($value -ne $parentAttributes) { throw 'Token parent attributes changed' }
    $entries = @([System.IO.Directory]::GetFileSystemEntries($fresh))
    if ($entries.Count -ne $parentEntries.Count) { throw 'Token entries changed' }
    foreach ($entry in $parentEntries) {
      if ($entries -cnotcontains $entry) { throw 'Token entry changed' }
    }
    $parentCode = 2
  } catch [System.UnauthorizedAccessException] { $parentCode = 1 }
  [Console]::WriteLine('GPTR_TOKEN ' + $phase + ' PARENT_LOOKUP ' + $parentCode)
  $probeCode = 4
  try { & $tokenProductionProbe }
  catch [System.UnauthorizedAccessException] { $probeCode = 1 }
  catch {
    if ($_.Exception.Message -ceq 'Existing writer directory') { $probeCode = 2 }
    else { throw }
  }
  [Console]::WriteLine('GPTR_TOKEN ' + $phase + ' PROBE ' + $probeCode)
  if ($fileCode -notin @(1, 2) -or $parentCode -notin @(1, 2) -or
      $probeCode -notin @(1, 2)) { throw 'Token lookup inconclusive' }
  if ($disabled) { $lease.VerifyDisabled() } else { $lease.VerifyOriginal() }
  [Console]::WriteLine('GPTR_TOKEN ' + $phase + ' TOKEN_EXACT 1')
  AssertTokenInputs
  [Console]::WriteLine('GPTR_TOKEN ' + $phase + ' ACL_EXACT 1')
}
try {
  # No token is opened until the enclosing finally is registered.
  $lease = [GptrCurrentToken]::new()
  ObserveTokenTrial 'A1' $false
  $lease.DisableGroup()
  ObserveTokenTrial 'B' $true
  $lease.Restore()
  ObserveTokenTrial 'A2' $false
} catch {
  $primaryFailure = $_
  [Console]::WriteLine('GPTR_TOKEN_FAILURE 1')
} finally {
  if ($null -ne $lease) {
    try {
      $lease.Restore()
      $tokenRestored = $true
      [Console]::WriteLine('GPTR_TOKEN END TOKEN_RESTORED 1')
    } catch {
      $cleanupFailure = $_
      [Console]::WriteLine('GPTR_TOKEN_FAILURE 2')
    } finally {
      try {
        $lease.Close()
        $tokenClosed = $true
        [Console]::WriteLine('GPTR_TOKEN END HANDLE_CLOSED 1')
      } catch {
        if ($null -eq $cleanupFailure) { $cleanupFailure = $_ }
        [Console]::WriteLine('GPTR_TOKEN_FAILURE 3')
      }
    }
  }
}
if ($null -ne $primaryFailure) { throw $primaryFailure }
if ($null -ne $cleanupFailure) { throw $cleanupFailure }
if (-not $tokenRestored -or -not $tokenClosed) { throw 'Token cleanup unverified' }
