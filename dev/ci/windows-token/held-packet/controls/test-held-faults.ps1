param([Parameter(Mandatory=$true)][string]$Fragment)
# Pure controls of the actual window. No compiler, native token, child or filesystem mutation.
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Stop'
. $Fragment
$originalFactory = (Get-Item Function:\NewHeldToken).ScriptBlock
$originalWriter = (Get-Item Function:\WriteHeldRecord).ScriptBlock
$passed = 0
try {
  foreach ($mode in @('normal', 'body-error', 'body-interrupt', 'partial-adjust',
      'disabled-query', 'restore-error', 'restore-interrupt', 'restore-query',
      'close-error', 'close-interrupt', 'report-error')) {
    $script:heldState = @{
      Mode = $mode; Bits = @(2, 2, 2); Calls = [System.Collections.Generic.List[string]]::new()
      Records = [System.Collections.Generic.List[string]]::new(); Body = 0; Closed = $false
      Primary = [System.InvalidOperationException]::new('PRIMARY-PUBLIC-FAULT')
      Cleanup = [System.InvalidOperationException]::new('CLEANUP-PUBLIC-FAULT')
    }
    if ($mode -ceq 'body-interrupt') {
      $script:heldState.Primary = [System.OperationCanceledException]::new('PRIMARY-CANCEL')
    }
    if ($mode -in @('restore-interrupt', 'close-interrupt')) {
      $script:heldState.Cleanup = [System.OperationCanceledException]::new('CLEANUP-CANCEL')
    }
    $script:heldLease = [pscustomobject]@{}
    $script:heldLease | Add-Member ScriptMethod VerifyOriginal {
      $script:heldState.Calls.Add('original')
      if ($script:heldState.Mode -ceq 'restore-query' -and
          $script:heldState.Calls.Contains('restore')) { throw $script:heldState.Cleanup }
      if (($script:heldState.Bits -join ',') -cne '2,2,2') { throw 'Original mismatch' }
    }
    $script:heldLease | Add-Member ScriptMethod DisableGroup {
      $script:heldState.Calls.Add('disable')
      if ($script:heldState.Mode -ceq 'partial-adjust') {
        $script:heldState.Bits = @(1, 2, 2)
        throw $script:heldState.Primary
      }
      $script:heldState.Bits = @(1, 1, 1)
    }
    $script:heldLease | Add-Member ScriptMethod VerifyDisabled {
      $script:heldState.Calls.Add('disabled')
      if ($script:heldState.Mode -ceq 'disabled-query') { throw $script:heldState.Primary }
      if (($script:heldState.Bits -join ',') -cne '1,1,1') { throw 'Disabled mismatch' }
    }
    $script:heldLease | Add-Member ScriptMethod StateCodes { return @(1, 1, 1) }
    $script:heldLease | Add-Member ScriptMethod Restore {
      $script:heldState.Calls.Add('restore')
      if ($script:heldState.Mode -in @('restore-error', 'restore-interrupt')) {
        throw $script:heldState.Cleanup }
      $script:heldState.Bits = @(2, 2, 2)
    }
    $script:heldLease | Add-Member ScriptMethod Close {
      $script:heldState.Calls.Add('close')
      if ($script:heldState.Mode -in @('close-error', 'close-interrupt')) {
        throw $script:heldState.Cleanup }
      $script:heldState.Closed = $true
    }
    function NewHeldToken { return $script:heldLease }
    function WriteHeldRecord([string]$record) {
      if ($script:heldState.Mode -ceq 'report-error' -and
          $record -ceq 'GPTR_HELD END TOKEN_RESTORED 1') { throw $script:heldState.Cleanup }
      $script:heldState.Records.Add($record)
    }
    $seen = $null
    try {
      InvokeHeldToken {
        $script:heldState.Body++
        if (($script:heldState.Bits -join ',') -cne '1,1,1') { throw 'Body not disabled' }
        if ($script:heldState.Mode -in @('body-error', 'body-interrupt')) {
          throw $script:heldState.Primary
        }
      }
    } catch { $seen = $_.Exception.GetBaseException() }
    if ($script:heldState.Calls.IndexOf('restore') -lt 0 -or
        $script:heldState.Calls.IndexOf('close') -le
        $script:heldState.Calls.IndexOf('restore')) { throw 'Independent cleanup missing' }
    $early = $mode -in @('partial-adjust', 'disabled-query')
    if ($script:heldState.Body -ne [int](-not $early)) { throw 'Body admission differs' }
    $primary = $mode -in @('body-error', 'body-interrupt', 'partial-adjust', 'disabled-query')
    $wanted = if ($primary) { $script:heldState.Primary } else { $script:heldState.Cleanup }
    if ($mode -ceq 'normal') {
      if ($null -ne $seen -or $script:heldState.Records.Count -ne 7) {
        throw 'Nominal window failed' }
    } elseif (-not [object]::ReferenceEquals($seen, $wanted)) {
      throw 'Original condition priority differs'
    }
    if ($mode -cnotin @('restore-error', 'restore-interrupt') -and
        ($script:heldState.Bits -join ',') -cne '2,2,2') {
      throw 'Final state differs' }
    if ($script:heldState.Closed -ne ($mode -cnotin @('close-error', 'close-interrupt'))) {
      throw 'Close differs' }
    if ($mode -in @('restore-error', 'restore-interrupt', 'restore-query') -and
        $script:heldState.Records.Contains('GPTR_HELD END TOKEN_RESTORED 1')) {
      throw 'False restoration proof' }
    if ($mode -in @('close-error', 'close-interrupt') -and
        $script:heldState.Records.Contains('GPTR_HELD END HANDLE_CLOSED 1')) {
      throw 'False closure proof' }
    $passed++
  }
  # Cleanup failure after a body error must not replace the exact primary exception.
  $script:heldState.Mode = 'restore-error'
  $script:heldState.Bits = @(2, 2, 2)
  $script:heldState.Calls.Clear()
  $script:heldState.Records.Clear()
  $seen = $null
  try { InvokeHeldToken { throw $script:heldState.Primary } }
  catch { $seen = $_.Exception.GetBaseException() }
  if (-not [object]::ReferenceEquals($seen, $script:heldState.Primary) -or
      -not $script:heldState.Calls.Contains('close')) { throw 'Cleanup replaced primary' }
  $passed++
  if ($passed -ne 12) { throw 'Fault control count differs' }
  [Console]::WriteLine('GPTR-HELD-FAULT-CONTROLS-12')
} finally {
  Set-Item Function:\NewHeldToken $originalFactory
  Set-Item Function:\WriteHeldRecord $originalWriter
  Remove-Variable heldState, heldLease -Scope Script
}
