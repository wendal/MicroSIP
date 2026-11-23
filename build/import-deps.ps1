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
        third_party\src\        source archives for everything we compile

    The archives in third_party\src are tracked with git-lfs, so a fresh clone
    gets them without any network access.

    The pjproject headers are derived from the pjproject archive itself, not
    from a separate dependency repository: upstream ships the headers under
    <component>/include/, and the application wants them flattened, i.e. all
    five components merged into one include tree:

        pjlib/include       ->  third_party\pj\...,      third_party\pjlib.h
        pjlib-util/include  ->  third_party\pjlib-util\...
        pjmedia/include     ->  third_party\pjmedia\..., third_party\pjmedia.h
        pjnath/include      ->  third_party\pjnath\...
        pjsip/include       ->  third_party\pjsip\...

    Because the flattened tree is a pure function of the archive, the vendored
    headers can be re-derived - and verified - at any time. The check lives in
    tools\verify-pjproject-provenance.ps1.

    Sources (all upstream, nothing private):
        * pjproject 2.17      - upstream release archive
        * OpenSSL 3.0.15      - upstream release archive
        * opus 1.3.1          - upstream release archive
        * bcg729              - upstream archive
        * SQLiteCpp 3.4.0     - upstream release archive

    Every file that ends up in third_party\src is recorded with its SHA-256 in
    third_party\MANIFEST.txt so the vendored copies can be verified later.

.EXAMPLE
    .\import-deps.ps1 `
        -PjZip         C:\src\pjproject-2.17.zip `
        -OpenSslZip    C:\src\openssl-3.0.15.zip `
        -OpusRoot      C:\src\opus-1.3.1 `
        -Bcg729Zip     C:\src\bcg729.zip `
        -SqliteCppZip  C:\src\SQLiteCpp-3.4.0.zip
#>
[CmdletBinding()]
param(
    # Every source location is explicit: the script must not depend on a
    # particular machine's directory layout.
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

New-Item -ItemType Directory -Force -Path $tp, $src, $lib | Out-Null

# ------------------------------------------------------------ source zips
Write-Host '--- source archives (git-lfs tracked) ---'

function Copy-Archive([string]$source, [string]$destName) {
    if (-not (Test-Path $source)) { throw "archive not found: $source" }
    $dest = Join-Path $src $destName
    Copy-Item $source $dest -Force
    Write-Host ("    {0,-26} {1,12:N0} bytes" -f $destName, (Get-Item $dest).Length)
}

Copy-Archive $PjZip 'pjproject-2.17.zip'
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

# --------------------------------------------------- pjproject headers
# The application includes the pjproject headers from one flat tree. Upstream
# keeps them per component, so the five include directories are merged.
Write-Host ''
Write-Host '--- pjproject headers (flattened from the archive) ---'

$components = @('pjlib', 'pjlib-util', 'pjmedia', 'pjnath', 'pjsip')

$unpack = Join-Path $env:TEMP ("pj-flat-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Force -Path $unpack | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $src 'pjproject-2.17.zip'), $unpack)
    # the archive has a single root directory - lift its content up
    $inner = Get-ChildItem $unpack -Directory | Select-Object -First 1
    if ($inner) {
        Get-ChildItem $inner.FullName -Force | ForEach-Object {
            Move-Item $_.FullName $unpack -Force
        }
        Remove-Item $inner.FullName -Recurse -Force
    }

    # relpath (below third_party\) -> file in the unpacked archive
    $flat = [ordered]@{}
    foreach ($c in $components) {
        $inc = Join-Path $unpack "$c\include"
        if (-not (Test-Path $inc)) { throw "missing $c\include in the pjproject archive" }
        foreach ($f in Get-ChildItem $inc -Recurse -File) {
            $rel = $f.FullName.Substring($inc.Length + 1)
            if ($flat.Contains($rel)) { throw "duplicate header path: $rel" }
            $flat[$rel] = $f.FullName
        }
    }

    # make sure a stale header tree cannot survive an upgrade: every top level
    # entry the new tree occupies is emptied first
    $tops = @{}
    foreach ($rel in $flat.Keys) {
        $tops[$rel.Split('\')[0]] = $true
    }
    foreach ($t in $tops.Keys) {
        $target = Join-Path $tp $t
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    }

    foreach ($rel in $flat.Keys) {
        $dest = Join-Path $tp $rel
        $dir = Split-Path $dest -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Copy-Item $flat[$rel] $dest -Force
    }
    Write-Host ("    {0,-18} {1,5} files" -f 'pjproject headers', $flat.Count)
    foreach ($t in ($tops.Keys | Sort-Object)) {
        $n = (Get-ChildItem (Join-Path $tp $t) -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Host ("      {0,-16} {1,5} files" -f $t, $n)
    }
} finally {
    Remove-Item $unpack -Recurse -Force -ErrorAction SilentlyContinue
}

# chkstk_ms.lib is NOT vendored: it does not exist for x86/x64 (it is an
# ARM64-only archive that Microsoft ships with the ARM64 toolchain, and
# microsip.vcxproj lists it in every configuration). build\steps\02-thirdparty.ps1
# generates a tiny placeholder instead - see build\stub\chkstk_ms.c.

# The pjproject static library is NOT vendored either: build\steps\03-pjproject.ps1
# compiles it from the archive above for every platform, so the application and
# the library it links against always come from the same pjproject release.

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
    # every path in the manifest is relative to third_party\
    $lines += ("{0}  src/{1}" -f $hash, $f.Name)
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
