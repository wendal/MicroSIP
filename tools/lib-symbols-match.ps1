<#
.SYNOPSIS
    Grep the exported symbols of a static library for a pattern.

.EXAMPLE
    .\lib-symbols-match.ps1 -Lib foo.lib -Pattern 'opus|ssl|tls|vpx|openh264|srtp'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Lib,
    [Parameter(Mandatory)][string]$Pattern,
    [string]$Dumpbin = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Dumpbin) {
    $Dumpbin = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio' -Recurse -Filter 'dumpbin.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*Hostx64\x86*' } | Select-Object -First 1 -ExpandProperty FullName
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Dumpbin
$psi.Arguments = "/nologo /symbols `"$Lib`""
$psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$p = [System.Diagnostics.Process]::Start($psi)
$out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()

$hits = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($line in ($out -split "`r?`n")) {
    if ($line -match 'External\s*\|\s*(\S+)') {
        $n = $matches[1]
        if ($n -match '^_*(pj[A-Za-z0-9_]+)$') {
            $sym = $matches[1]          # capture BEFORE the next -match resets $matches
            if ($sym -match $Pattern) { [void]$hits.Add($sym) }
        }
    }
}
"lib : $Lib"
"pattern '$Pattern' -> $($hits.Count) symbols"
$hits | Sort-Object | ForEach-Object { "   $_" }
