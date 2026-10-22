<#
.SYNOPSIS
    Compile and run a self test against the static OpenSSL MicroSIP links.

.DESCRIPTION
    Builds tools\openssl-selftest\selftest.c against the very same archives
    that end up inside microsip.exe
    (third_party\openssl\<Platform>\<Configuration>\lib\{libcrypto,libssl}.lib)
    and runs it.

    It answers three questions that a successful link alone cannot:
      * is the OpenSSL build really static (no DLL at run time)?
      * did the provider archives (providers\libdefault.lib, libcommon.lib)
        make it into the link? OSSL_PROVIDER_load("default") fails with
        "module not found" otherwise.
      * can a TLS context be created at all?

.EXAMPLE
    .\verify-openssl.ps1 -Platform x64 -Configuration Debug
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

if (-not $Source) {
    $Source = Join-Path $PSScriptRoot 'openssl-selftest\selftest.c'
}
if (-not (Test-Path $Source)) { throw "source not found: $Source" }

$libDir = Join-Path $Root "third_party\openssl\$Platform\$Configuration\lib"
$libCrypto = Join-Path $libDir 'libcrypto.lib'
$libSsl = Join-Path $libDir 'libssl.lib'
foreach ($l in @($libCrypto, $libSsl)) {
    if (-not (Test-Path $l)) { throw "not found: $l  (run tools\build-openssl.ps1 first)" }
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

$work = Join-Path $Root "build\work\openssl-selftest-$Platform-$Configuration"
New-Item -ItemType Directory -Force -Path $work | Out-Null
$obj = Join-Path $work 'selftest.obj'
$exe = Join-Path $work 'selftest.exe'
if (Test-Path $exe) { Remove-Item $exe -Force }

Write-Host "platform     : $Platform"
Write-Host "configuration: $Configuration  (CRT $crt)"
Write-Host "libraries    : $libDir"
Write-Host ''

Push-Location $work
try {
    & $envInfo.Cl /nologo /c $crt /O2 /W0 "/I$(Join-Path $Root 'third_party\openssl\Win32\include')" $Source "/Fo:$obj"
    if ($LASTEXITCODE -ne 0) { throw 'compile failed' }

    # same order as pjlib's pragma: libcrypto, libssl
    # cl.exe forwards the library names to link.exe; the search path has to
    # come from the LIB environment variable, /LIBPATH is not a compiler option
    # ws2_32/crypt32/advapi32/user32 are the Windows libraries OpenSSL's
    # socket BIO and the CryptoAPI engine pull in
    $env:LIB = "$libDir;$env:LIB"
    & $envInfo.Cl /nologo "/Fe:$exe" $obj libcrypto.lib libssl.lib ws2_32.lib crypt32.lib advapi32.lib user32.lib
    if ($LASTEXITCODE -ne 0) { throw 'link failed' }
} finally {
    Pop-Location
}

Write-Host '--- running ---'
& $exe
$rc = $LASTEXITCODE
Write-Host ''
Write-Host "exit code: $rc"
if ($rc -ne 0) { throw "self test failed ($rc)" }
Write-Host 'RESULT: OK'
