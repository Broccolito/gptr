param([string]$Stage, [string]$Native)
$ErrorActionPreference = 'Stop'
[System.IO.File]::WriteAllText($Stage, 'script-entered')
[Console]::WriteLine('GPTR-PS-STARTUP-ENTERED')
$names = @('SystemRoot', 'Path', 'TEMP', 'WINDIR', 'USERPROFILE')
$bits = [int[]]@(foreach ($name in $names) {
  -not [String]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name, 'Process'))
})
[Console]::WriteLine('GPTR-PS-ENV=' + [String]::Join(',', [string[]]$bits))
$actual = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$nativeEqual = [String]::Equals(
  [System.IO.Path]::GetFullPath($actual),
  [System.IO.Path]::GetFullPath($Native), [StringComparison]::OrdinalIgnoreCase)
[Console]::WriteLine('GPTR-PS-NATIVE=' + [int]$nativeEqual)
[System.IO.File]::WriteAllText($Stage, 'done')
[Console]::WriteLine('GPTR-PS-STARTUP-DONE')
