# R 4.2 needs the PDF checker explicitly even when no C compiler is needed.
$qpdf = Get-ChildItem 'C:\rtools*\usr\bin\qpdf.exe' -File -ErrorAction Stop |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $qpdf) { throw 'The hosted image must provide qpdf in its preinstalled Rtools.' }
& $qpdf.FullName --version
if ($LASTEXITCODE -ne 0) { throw 'The preinstalled qpdf could not run.' }
"R_QPDF=$($qpdf.FullName)" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
