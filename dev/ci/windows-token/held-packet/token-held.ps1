# Test-only current-utility window. The factory accepts no PID, handle or privilege input.
function NewHeldToken { return [GptrCurrentToken]::new() }
function WriteHeldRecord([string]$record) { [Console]::WriteLine($record) }

function InvokeHeldToken([scriptblock]$body) {
  $lease = $null
  $primaryFailure = $null
  $cleanupFailure = $null
  $tokenRestored = $false
  $tokenClosed = $false
  try {
    $lease = NewHeldToken
    if ($null -eq $lease) { throw 'Held token constructor unknown' }
    $lease.VerifyOriginal()
    $lease.DisableGroup()
    $lease.VerifyDisabled()
    $codes = $lease.StateCodes()
    if ($codes.Length -ne 3 -or $codes[0] -ne 1 -or $codes[1] -ne 1 -or
        $codes[2] -ne 1) { throw 'Held token disabled state unknown' }
    WriteHeldRecord 'GPTR_HELD B BACKUP 1'
    WriteHeldRecord 'GPTR_HELD B RESTORE 1'
    WriteHeldRecord 'GPTR_HELD B CHANGE_NOTIFY 1'
    WriteHeldRecord 'GPTR_HELD B TOKEN_EXACT 1'
    # Dot sourcing retains this window's variables; outer ACL snapshots remain readable.
    . $body
    $lease.VerifyDisabled()
    WriteHeldRecord 'GPTR_HELD END BODY 1'
  } catch {
    $primaryFailure = $_
  } finally {
    if ($null -ne $lease) {
      try {
        $lease.Restore()
        $lease.VerifyOriginal()
        $tokenRestored = $true
      } catch {
        $cleanupFailure = $_
      } finally {
        try {
          $lease.Close()
          $tokenClosed = $true
        } catch {
          if ($null -eq $cleanupFailure) { $cleanupFailure = $_ }
        }
      }
    }
  }
  # Reporting is attempted after both cleanup operations and cannot replace the primary.
  try {
    if ($tokenRestored) { WriteHeldRecord 'GPTR_HELD END TOKEN_RESTORED 1' }
    if ($tokenClosed) { WriteHeldRecord 'GPTR_HELD END HANDLE_CLOSED 1' }
  } catch {
    if ($null -eq $cleanupFailure) { $cleanupFailure = $_ }
  }
  if ($null -ne $primaryFailure) { throw $primaryFailure }
  if ($null -ne $cleanupFailure) { throw $cleanupFailure }
  if (-not $tokenRestored -or -not $tokenClosed) { throw 'Held token cleanup unverified' }
}
