<#
.SYNOPSIS
    End-to-end check: create a real SIP-over-TLS transport with the locally
    built x64 pjproject.

.DESCRIPTION
    Builds tools\tls-selftest\tlstest.cpp against the same static pjproject
    library MicroSIP links (third_party tree + lib\libpjproject-x86_64-x64-
    vc14-<Configuration>-Static.lib) and runs it.

    The test asks pjsua to create a PJSIP_TRANSPORT_TLS transport, which makes
    pjlib build an OpenSSL SSL_CTX. A failure means the TLS backend is not
    usable even though the binary links.

.EXAMPLE
    .\verify-tls.ps1 -Platform x64 -Configuration Debug
#>
[CmdletBinding()]
param(
    [ValidateSet('x64', 'Win32')][string]$Platform = 'x64',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [string]$RepoRoot = '',
    [string]$Source = ''
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$Root = $RepoRoot

if (-not $Source) { $Source = Join-Path $PSScriptRoot 'tls-selftest\tlstest.cpp' }
if (-not (Test-Path $Source)) { throw "source not found: $Source" }

$pjLib = Join-Path $Root "third_party\lib\libpjproject-x86_64-x64-vc14-$Configuration-Static.lib"
if (-not (Test-Path $pjLib)) { throw "not found: $pjLib  (run build\build.ps1 first)" }

$osslDir = Join-Path $Root "third_party\openssl\$Platform\$Configuration\lib"
$opusDir = Join-Path $Root "third_party\opus\$Platform\$Configuration"
foreach ($d in @($osslDir, $opusDir)) {
    if (-not (Test-Path $d)) { throw "not found: $d" }
}

# ---------------------------------------------------------------- MSVC env
function Get-MsvcEnv([string]$arch) {
    $vsRoot = $null
    foreach ($v in @('18', '2022')) {
        $c = "C:\Program Files\Microsoft Visual Studio\$v"
        if (Test-Path $c) { $vsRoot = $c; break }
    }
    if (-not $vsRoot) { throw 'Visual Studio not found' }

    $hostArch = if ($arch -eq 'x64') { 'x64' } else { 'x86' }
    $clExe = Get-ChildItem "$vsRoot\*\VC\Tools\MSVC\*\bin\Hostx64\$hostArch\cl.exe" -File -ErrorAction SilentlyContinue |
             Sort-Object { [version]($_.FullName -split 'MSVC\\')[1].Split('\')[0] } -Descending |
             Select-Object -First 1
    if (-not $clExe) { throw "cl.exe not found for $arch" }
    $vcRoot = $clExe.FullName -replace '\\bin\\Hostx64\\[^\\]+\\cl\.exe$', ''

    $sdkRoot = 'C:\Program Files (x86)\Windows Kits\10'
    $sdkVer = Get-ChildItem "$sdkRoot\Include" -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
              Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $sdkVer) { throw 'Windows SDK not found' }

    $libArch = if ($arch -eq 'x64') { 'x64' } else { 'x86' }
    $sdkInc = Join-Path $sdkRoot "Include\$($sdkVer.Name)"
    $sdkLib = Join-Path $sdkRoot "Lib\$($sdkVer.Name)"

    $env:INCLUDE = @(
        (Join-Path $vcRoot 'include'),
        (Join-Path $sdkInc 'ucrt'), (Join-Path $sdkInc 'um'),
        (Join-Path $sdkInc 'shared'), (Join-Path $sdkInc 'winrt')
    ) -join ';'
    $env:LIB = @(
        (Join-Path $vcRoot "lib\$libArch"),
        (Join-Path $sdkLib "ucrt\$libArch"), (Join-Path $sdkLib "um\$libArch")
    ) -join ';'
    $env:Path = (Join-Path $vcRoot "bin\Hostx64\$hostArch") + ';' + $env:Path

    return [pscustomobject]@{ Cl = $clExe.FullName }
}

$envInfo = Get-MsvcEnv $Platform
$crt = if ($Configuration -eq 'Debug') { '/MTd' } else { '/MT' }

$work = Join-Path $Root "build\work\tls-selftest-$Platform-$Configuration"
New-Item -ItemType Directory -Force -Path $work | Out-Null
$obj = Join-Path $work 'tlstest.obj'
$exe = Join-Path $work 'tlstest.exe'
if (Test-Path $exe) { Remove-Item $exe -Force }

$tp = Join-Path $Root 'third_party'

Write-Host "platform     : $Platform"
Write-Host "configuration: $Configuration  (CRT $crt)"
Write-Host "pjproject lib: $pjLib"
Write-Host ''

Push-Location $work
try {
    & $envInfo.Cl /nologo /c /EHsc /std:c++14 $crt /O2 /W0 `
        "/I$tp" "/I$(Join-Path $tp 'openssl\Win32\include')" `
        $Source "/Fo:$obj"
    if ($LASTEXITCODE -ne 0) { throw 'compile failed' }

    # libcrypto/libssl come in through the pragma inside pjlib's
    # ssl_sock_ossl.c, opus.lib through the pragma in pjmedia-codec's opus.c
    $env:LIB = "$osslDir;$opusDir;$env:LIB"
    & $envInfo.Cl /nologo "/Fe:$exe" $obj $pjLib ws2_32.lib crypt32.lib advapi32.lib user32.lib ole32.lib
    if ($LASTEXITCODE -ne 0) { throw 'link failed' }
} finally {
    Pop-Location
}

Write-Host '--- running ---'
& $exe
$rc = $LASTEXITCODE
Write-Host ''
Write-Host "exit code: $rc"
if ($rc -ne 0) { throw "TLS self test failed ($rc)" }
Write-Host 'RESULT: OK'
