<#
.SYNOPSIS
    One-off bootstrap: fill third_party\ of this repository from the upstream
    dependency sources.

.DESCRIPTION
    The repository is meant to be self-contained: after this script has run
    once, `git clone` + `build\build.ps1` is enough to produce microsip.exe.

    This script is what creates that state. It is NOT part of the build; it is
    the step that vendors the dependencies into the repository:

        third_party\            pjproject headers (upstream layout, flattened)
        third_party\lib\        prebuilt 32-bit pjproject + chkstk_ms.lib
        third_party\src\        source archives for everything we compile

    The archives in third_party\src are tracked with git-lfs, so a fresh clone
    gets them without any network access.

    Sources (all upstream, nothing private):
        * MicroSIP-Com-Deps  - the official dependency repository that
                                microsip.org/source refers to
        * pjproject 2.14.1    - upstream release archive
        * OpenSSL 3.0.15      - upstream release archive
        * opus 1.3.1          - upstream release archive
        * bcg729              - upstream archive
        * SQLiteCpp 3.4.0     - upstream release archive

    Every file that ends up in third_party\src is recorded with its SHA-256 in
    third_party\MANIFEST.txt so the vendored copies can be verified later.

.EXAMPLE
    .\import-deps.ps1 `
        -ComDepsRoot   C:\src\MicroSIP-Com-Deps-main `
        -PjZip         C:\src\pjproject-2.14.1.zip `
        -OpenSslZip    C:\src\openssl-3.0.15.zip `
        -OpusRoot      C:\src\opus-1.3.1 `
        -Bcg729Zip     C:\src\bcg729.zip `
        -SqliteCppZip  C:\src\SQLiteCpp-3.4.0.zip
#>
[CmdletBinding()]
param(
    # Every source location is explicit: the script must not depend on a
    # particular machine's directory layout.
    [Parameter(Mandatory = $true)][string]$ComDepsRoot,
    [Parameter(Mandatory = $true)][string]$PjZip,
    [Parameter(Mandatory = $true)][string]$OpenSslZip,
    [Parameter(Mandatory = $true)][string]$OpusRoot,
    [Parameter(Mandatory = $true)][string]$Bcg729Zip,
    [Parameter(Mandatory = $true)][string]$SqliteCppZip,
    [string]$Repo = '',
    [switch]$SkipOpusArchive
)

$ErrorActionPreference = 'Stop'

if (-not $Repo) { $Repo = Split-Path $PSScriptRoot -Parent }
$tp = Join-Path $Repo 'third_party'
$src = Join-Path $tp 'src'
$lib = Join-Path $tp 'lib'

Write-Host "repo        : $Repo"
Write-Host "third_party : $tp"
Write-Host ''

# ------------------------------------------------------------- headers
if (-not (Test-Path $ComDepsRoot)) { throw "MicroSIP-Com-Deps not found: $ComDepsRoot" }
$comDepsTp = Join-Path $ComDepsRoot 'third_party'
if (-not (Test-Path $comDepsTp)) { throw "no third_party in $ComDepsRoot" }

New-Item -ItemType Directory -Force -Path $tp, $src, $lib | Out-Null

Write-Host '--- pjproject headers (from MicroSIP-Com-Deps) ---'
$copied = 0
foreach ($d in Get-ChildItem $comDepsTp -Directory) {
    if ($d.Name -eq 'lib') { continue }
    $dest = Join-Path $tp $d.Name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $d.FullName $dest -Recurse -Force
    $copied += (Get-ChildItem $dest -Recurse -File).Count
    Write-Host ("    {0,-18} {1,5} files" -f $d.Name, (Get-ChildItem $dest -Recurse -File).Count)
}
foreach ($f in Get-ChildItem $comDepsTp -File) {
    Copy-Item $f.FullName (Join-Path $tp $f.Name) -Force
    $copied++
}
Write-Host "    header files copied: $copied"

# ------------------------------------------------------ prebuilt archives
Write-Host ''
Write-Host '--- prebuilt libraries ---'
# the official 32-bit pjproject library: needed because rebuilding pjproject
# for Win32 is out of scope (the Win32 build of the app links this one)
$official32 = Join-Path $comDepsTp 'lib\libpjproject-i386-Win32-vc14-Debug-Static.lib'
if (-not (Test-Path $official32)) { throw "official 32-bit pjproject library not found: $official32" }
Copy-Item $official32 (Join-Path $lib 'libpjproject-i386-Win32-vc14-Debug-Static.lib') -Force
Write-Host "    libpjproject-i386-Win32-vc14-Debug-Static.lib"

# chkstk_ms.lib is NOT vendored: it does not exist for x86/x64 (it is an
# ARM64-only archive that Microsoft ships with the ARM64 toolchain, and
# microsip.vcxproj lists it in every configuration). build\steps\02-thirdparty.ps1
# generates a tiny placeholder instead - see build\stub\chkstk_ms.c.

# ------------------------------------------------------------ source zips
Write-Host ''
Write-Host '--- source archives (git-lfs tracked) ---'

function Copy-Archive([string]$source, [string]$destName) {
    if (-not (Test-Path $source)) { throw "archive not found: $source" }
    $dest = Join-Path $src $destName
    Copy-Item $source $dest -Force
    Write-Host ("    {0,-26} {1,12:N0} bytes" -f $destName, (Get-Item $dest).Length)
}

Copy-Archive $PjZip 'pjproject-2.14.1.zip'
Copy-Archive $OpenSslZip 'openssl-3.0.15.zip'
Copy-Archive $Bcg729Zip 'bcg729.zip'
Copy-Archive $SqliteCppZip 'SQLiteCpp-3.4.0.zip'

if (-not $SkipOpusArchive) {
    if (-not (Test-Path $OpusRoot)) { throw "opus source not found: $OpusRoot" }
    # only the parts the Visual Studio project needs
    $staging = Join-Path $env:TEMP ("opus-pack-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    try {
        foreach ($part in @('include', 'src', 'celt', 'silk', 'win32')) {
            Copy-Item (Join-Path $OpusRoot $part) (Join-Path $staging $part) -Recurse -Force
        }
        Copy-Item (Join-Path $OpusRoot 'package_version') $staging -Force
        Copy-Item (Join-Path $OpusRoot 'COPYING') $staging -Force
        $opusZip = Join-Path $src 'opus-1.3.1.zip'
        if (Test-Path $opusZip) { Remove-Item $opusZip -Force }
        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $opusZip -CompressionLevel Optimal
        Write-Host ("    {0,-26} {1,12:N0} bytes" -f 'opus-1.3.1.zip', (Get-Item $opusZip).Length)
    } finally {
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --------------------------------------------------------------- manifest
Write-Host ''
Write-Host '--- manifest ---'
$manifest = Join-Path $tp 'MANIFEST.txt'
$lines = @(
    '# third_party dependency manifest',
    '# generated by build\import-deps.ps1 - SHA-256 of every vendored archive',
    ''
)
foreach ($f in Get-ChildItem $src -File | Sort-Object Name) {
    $hash = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower()
    $lines += ("{0}  {1}" -f $hash, $f.Name)
}
$lines += ''
$lines += '# prebuilt libraries'
foreach ($f in Get-ChildItem $lib -File | Sort-Object Name) {
    $hash = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower()
    $lines += ("{0}  lib/{1}" -f $hash, $f.Name)
}
Set-Content -Path $manifest -Value ($lines -join "`r`n") -Encoding utf8
Write-Host "    $manifest"

Write-Host ''
Write-Host '=== third_party layout ==='
Get-ChildItem $tp -Force | ForEach-Object {
    if ($_.PSIsContainer) {
        $n = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
        "    {0,-18} {1,6} files" -f $_.Name, $n
    } else {
        "    {0,-18} {1,12:N0} bytes" -f $_.Name, $_.Length
    }
}
