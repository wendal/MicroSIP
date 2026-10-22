<#
.SYNOPSIS
    Verify the vendored dependency archives against third_party\MANIFEST.txt.

.DESCRIPTION
    MANIFEST.txt lists the SHA-256 of every vendored archive. Every path in
    it is relative to the third_party folder. This script recomputes the
    hashes and reports anything that is missing or does not match - which is
    what you want after a fresh clone, to prove that the git-lfs payloads
    arrived intact.

.PARAMETER ThirdParty
    The third_party folder. Defaults to the one next to this script.

.EXAMPLE
    .\tools\verify-manifest.ps1
#>
[CmdletBinding()]
param(
    [string]$ThirdParty = ''
)

$ErrorActionPreference = 'Stop'

if (-not $ThirdParty) {
    $ThirdParty = Join-Path (Split-Path $PSScriptRoot -Parent) 'third_party'
}
$manifest = Join-Path $ThirdParty 'MANIFEST.txt'
if (-not (Test-Path $manifest)) { throw "manifest not found: $manifest" }

$entries = Get-Content $manifest | Where-Object { $_ -and -not $_.StartsWith('#') }
if (-not $entries) { throw "manifest is empty: $manifest" }

$failed = 0
$ok = 0
foreach ($line in $entries) {
    $parts = $line -split '\s+', 2
    if ($parts.Count -ne 2) {
        Write-Host ("   [BAD]  malformed line: {0}" -f $line) -ForegroundColor Yellow
        $failed++
        continue
    }
    $hash = $parts[0].Trim()
    $rel = $parts[1].Trim()
    $file = Join-Path $ThirdParty ($rel -replace '/', '\')
    if (-not (Test-Path $file)) {
        Write-Host ("   [MISS] {0}" -f $rel) -ForegroundColor Yellow
        $failed++
        continue
    }
    $actual = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
    if ($actual -eq $hash.ToLower()) {
        Write-Host ("   [ok]   {0}  ({1:N0} bytes)" -f $rel, (Get-Item $file).Length)
        $ok++
    } else {
        Write-Host ("   [BAD]  {0}" -f $rel) -ForegroundColor Red
        Write-Host ("         expected {0}" -f $hash)
        Write-Host ("         actual   {0}" -f $actual)
        $failed++
    }
}

Write-Host ''
if ($failed -eq 0) {
    Write-Host ("RESULT: all {0} vendored archives match the manifest." -f $ok) -ForegroundColor Green
    exit 0
}
Write-Host ("RESULT: {0} of {1} archives failed." -f $failed, ($ok + $failed)) -ForegroundColor Red
exit 1
