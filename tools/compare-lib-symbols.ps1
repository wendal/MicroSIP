<#
.SYNOPSIS
    Compare the exported pj* symbol sets of two pjproject static libraries.

.DESCRIPTION
    Use this to find out what a freshly built library is missing relative to a
    reference build (e.g. the official 32-bit MicroSIP library): the opus
    codec, libvpx, openh264, SRTP/TLS support and so on show up as absent
    symbols.

.EXAMPLE
    .\compare-lib-symbols.ps1 -LibA old.lib -LibB new.lib
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LibA,
    [Parameter(Mandatory)][string]$LibB,
    [string]$Dumpbin = ''
)

$ErrorActionPreference = 'Stop'

function Get-Dumpbin {
    if ($Dumpbin -and (Test-Path $Dumpbin)) { return $Dumpbin }
    Get-ChildItem 'C:\Program Files\Microsoft Visual Studio' -Recurse -Filter 'dumpbin.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*Hostx64\x86*' } | Select-Object -First 1 -ExpandProperty FullName
}

function Get-Symbols([string]$lib, [string]$dump) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $dump
    $psi.Arguments = "/nologo /symbols `"$lib`""
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($line in ($out -split "`r?`n")) {
        if ($line -match 'External\s*\|\s*(\S+)') {
            $n = $matches[1]
            # x86 C symbols carry a leading underscore, x64 ones do not
            if ($n -match '^_*(pj[A-Za-z0-9_]+)$') { [void]$set.Add($matches[1]) }
        }
    }
    return $set
}

$dump = Get-Dumpbin
if (-not $dump) { throw 'dumpbin.exe not found' }

$a = Get-Symbols $LibA $dump
$b = Get-Symbols $LibB $dump

"A: $LibA"
"   symbols: $($a.Count)"
"B: $LibB"
"   symbols: $($b.Count)"
''
$onlyA = @($a | Where-Object { -not $b.Contains($_) } | Sort-Object)
$onlyB = @($b | Where-Object { -not $a.Contains($_) } | Sort-Object)
"only in A (missing from B) : $($onlyA.Count)"
$onlyA | ForEach-Object { "   $_" }
"only in B (extra in B)     : $($onlyB.Count)"
$onlyB | Select-Object -First 40 | ForEach-Object { "   $_" }
