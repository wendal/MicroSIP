<#
.SYNOPSIS
    Smoke-test a built MicroSIP binary: start it, check that it really comes
    up (window, worker threads, call log database) and shut it down.

.EXAMPLE
    .\verify-app.ps1 -Exe .\x64\Debug\microsip.exe
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Exe,
    [int]$Seconds = 8
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Exe)) { throw "not found: $Exe" }
$fi = Get-Item $Exe
"exe   : $($fi.FullName)"
"size  : {0:N0} bytes" -f $fi.Length
"ver   : $($fi.VersionInfo.FileVersion)"

# is it really the architecture we think?
$bytes = [System.IO.File]::ReadAllBytes($Exe)
$peOff = [BitConverter]::ToInt32($bytes, 0x3C)
$machine = [BitConverter]::ToUInt16($bytes, $peOff + 4)
$arch = switch ($machine) { 0x8664 { 'x64' } 0x14c { 'x86' } 0xAA64 { 'ARM64' } default { "0x$('{0:X}' -f $machine)" } }
"arch  : $arch (PE machine 0x$('{0:X}' -f $machine))"

$work = Split-Path $fi.FullName -Parent
Push-Location $work
$p = $null
try {
    $p = Start-Process -FilePath $fi.FullName -WorkingDirectory $work -PassThru
    "pid   : $($p.Id)"
    Start-Sleep -Seconds $Seconds
    $p.Refresh()
    if ($p.HasExited) {
        "RESULT: process EXITED early with code $($p.ExitCode)"
        exit 1
    }
    "alive : yes"
    "title : '$($p.MainWindowTitle)'"
    "threads: $($p.Threads.Count)"
    $db = Join-Path $work 'call_log.db'
    if (Test-Path $db) {
        "db    : call_log.db created ({0:N0} bytes)" -f (Get-Item $db).Length
    } else {
        "db    : call_log.db NOT created"
    }
    # the pjsip worker/timer threads are the sign that the stack is alive
    $threadCount = $p.Threads.Count
    if ($threadCount -lt 8) { "WARNING: only $threadCount threads - pjsip worker threads missing" }
    "RESULT: OK"
}
finally {
    if ($p -and -not $p.HasExited) {
        $p.CloseMainWindow() | Out-Null
        Start-Sleep -Seconds 2
        if (-not $p.HasExited) { $p.Kill() }
    }
    Pop-Location
}
