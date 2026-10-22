<#
.SYNOPSIS
    Step 1 - unpack the vendored sources and stage the third-party headers.

.DESCRIPTION
    Everything the build needs is inside this repository:

        third_party\src\*.zip       source archives (git-lfs tracked)
        third_party\*.h, \pj\ ...   pjproject headers (already in the repo)

    This step unpacks the archives into build\work\ and copies the headers the
    compiler needs into the third_party tree:

        opus      -> third_party\opus\include\opus\
        bcg729    -> third_party\bcg729\include\bcg729\
        SQLiteCpp -> third_party\SQLiteCpp\            (sqlite3.h)
                   -> third_party\SQLiteCpp\SQLiteCpp\   (the wrapper headers)
        OpenSSL   -> third_party\openssl\Win32\include\openssl\

    It also generates pj\config_site.h - once for the application (in
    third_party\) and once for the pjproject build tree. Both files have to be
    identical: the macros decide what is compiled into the library and what the
    application believes the library contains.

    The macros are guarded by #if defined(_M_X64). The x64 library that is
    built here has Opus and TLS; the prebuilt 32-bit library that ships with
    MicroSIP was compiled without them, so the Win32 build of the application
    must see exactly the same macro set as the library it links against.

.EXAMPLE
    .\01-prepare.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [switch]$NoOpus,
    [switch]$NoSsl
)

. (Join-Path $PSScriptRoot '_common.ps1')

if (-not $RepoRoot) { $RepoRoot = Get-RepoRoot }
$work = Get-WorkDir $RepoRoot
$tp = Join-Path $RepoRoot 'third_party'
$srcDir = Join-Path $tp 'src'

New-Item -ItemType Directory -Force -Path $work | Out-Null

Write-Step 'unpacking vendored sources'

function Unpack([string]$zipName, [string]$destName, [string]$expect) {
    $zip = Join-Path $srcDir $zipName
    if (-not (Test-Path $zip)) { throw "missing archive: $zip" }
    $dest = Join-Path $work $destName
    # The marker is written only after a complete extraction, so an
    # interrupted unpack is redone instead of being taken for finished.
    $marker = Join-Path $dest '.unpacked'
    if (Test-Path $marker) {
        Write-Ok ("{0,-24} already unpacked" -f $zipName)
        return $dest
    }
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
    # GitHub archives unpack into "<repo>-<tag>", upstream ones into the
    # plain name - normalise to the expected directory.
    $inner = Get-ChildItem $dest -Directory | Where-Object { $_.Name -ne '__MACOSX' } | Select-Object -First 1
    if ($inner -and -not (Test-Path (Join-Path $dest $expect))) {
        # the archive has a single root directory - lift its content up
        Get-ChildItem $inner.FullName -Force | ForEach-Object {
            Move-Item $_.FullName $dest -Force
        }
        Remove-Item $inner.FullName -Recurse -Force
    }
    if (-not (Test-Path (Join-Path $dest $expect))) {
        throw "$zipName did not contain '$expect'"
    }
    Set-Content -Path $marker -Value 'ok' -Encoding ascii
    Write-Ok ("{0,-24} -> build\work\{1}" -f $zipName, $destName)
    return $dest
}

$pjTree = Unpack 'pjproject-2.14.1.zip' 'pjproject-2.14.1' 'pjlib'
$sslTree = Unpack 'openssl-3.0.15.zip' 'openssl-3.0.15' 'include'
$opusTree = Unpack 'opus-1.3.1.zip' 'opus-1.3.1' 'include'
$bcgTree = Unpack 'bcg729.zip' 'bcg729' 'include'
$sqlTree = Unpack 'SQLiteCpp-3.4.0.zip' 'SQLiteCpp-3.4.0' 'include'

Write-Step 'staging third-party headers'

function Stage-Tree([string]$from, [string]$to, [string]$label) {
    if (-not (Test-Path $from)) { throw "missing header source: $from" }
    New-Item -ItemType Directory -Force -Path $to | Out-Null
    Copy-Item $from\* $to -Recurse -Force
    Write-Ok ("{0,-12} {1,4} files -> {2}" -f $label, (Get-ChildItem $to -Recurse -File).Count, $to.Substring($RepoRoot.Length + 1))
}

if (-not $NoOpus) {
    Stage-Tree (Join-Path $opusTree 'include') (Join-Path $tp 'opus\include\opus') 'opus'
}
Stage-Tree (Join-Path $bcgTree 'include\bcg729') (Join-Path $tp 'bcg729\include\bcg729') 'bcg729'
Stage-Tree (Join-Path $sqlTree 'include\SQLiteCpp') (Join-Path $tp 'SQLiteCpp\SQLiteCpp') 'SQLiteCpp'
Copy-Item (Join-Path $sqlTree 'sqlite3\sqlite3.h') (Join-Path $tp 'SQLiteCpp\sqlite3.h') -Force
Write-Ok 'sqlite3.h     -> third_party\SQLiteCpp\sqlite3.h'
# The OpenSSL headers are staged by step 2 instead: OpenSSL generates
# opensslconf.h, configuration.h and friends during "Configure", and only the
# configured tree has them.

Write-Step 'generating pj\config_site.h'

$sample = Join-Path $pjTree 'pjlib\include\pj\config_site_sample.h'
if (-not (Test-Path $sample)) { throw "missing $sample" }

$cfg = Get-Content $sample -Raw
# drop a previously generated local block
$cfg = [regex]::Replace($cfg, '(?s)\r?\n/\* --- local build configuration \(MicroSIP\) --- \*/.*?#endif\r?\n', "`r`n")

$macros = @()
if (-not $NoOpus) { $macros += 'PJMEDIA_HAS_OPUS_CODEC' }
if (-not $NoSsl) { $macros += 'PJ_HAS_SSL_SOCK' }

$blockLines = @()
$blockLines += ''
$blockLines += '/* --- local build configuration (MicroSIP) --- */'
$blockLines += '#define PJMEDIA_HAS_VIDEO 1'
$blockLines += ''
$blockLines += '/* Features that only the locally built x64 pjproject provides. The 32-bit'
$blockLines += ' * library shipped with MicroSIP was built without them, so the Win32 build'
$blockLines += ' * must see the same macro set as the library it links against. */'
$blockLines += '#if defined(_M_X64)'
foreach ($m in $macros) { $blockLines += "#  define $m 1" }
$blockLines += '#else'
foreach ($m in $macros) { $blockLines += "#  define $m 0" }
$blockLines += '#endif'
$block = ($blockLines -join "`r`n") + "`r`n"

$marker = '*/'
$idx = $cfg.IndexOf($marker)
if ($idx -lt 0) { throw 'unexpected config_site_sample.h layout' }
$idx += $marker.Length
$cfg = $cfg.Substring(0, $idx) + "`r`n" + $block + $cfg.Substring($idx)

$targets = @(
    (Join-Path $tp 'pj\config_site.h'),
    (Join-Path $pjTree 'pjlib\include\pj\config_site.h')
)
foreach ($t in $targets) {
    $same = (Test-Path $t) -and ((Get-Content $t -Raw) -eq $cfg)
    if (-not $same) { Set-Content -Path $t -Value $cfg -Encoding utf8 -NoNewline }
    Write-Ok ("{0}" -f $t.Substring($RepoRoot.Length + 1))
}

Write-Host ''
Write-Host 'RESULT: dependencies prepared.' -ForegroundColor Green
