<#
.SYNOPSIS
    Build MicroSIP from this repository alone.

.DESCRIPTION
    Single entry point for the whole pipeline. Everything it needs is inside
    the repository:

        third_party\        pjproject headers + the prebuilt 32-bit library
        third_party\src\    source archives for everything that is compiled
                            (git-lfs tracked, so a clone brings them along)

    The steps are:

        0  check-toolchain   report every missing tool (and how to install it)
        1  prepare           unpack the archives, stage the third-party headers,
                            generate pj\config_site.h
        2  thirdparty        build SQLiteCpp, bcg729, opus, OpenSSL and the
                            chkstk_ms placeholder - per platform and
                            configuration, with the matching CRT
        3  pjproject         build the pjproject static library for x64
        4  app               build microsip.vcxproj

    Nothing is downloaded: if third_party\src is empty, run
    build\import-deps.ps1 once (it needs the upstream archives) or make sure
    git-lfs pulled them.

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Platform x64 -Configuration Debug
    .\build.ps1 -Step app -Platform x64
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release', 'All')][string]$Configuration = 'All',
    [ValidateSet('x64', 'Win32', 'All')][string]$Platform = 'All',
    [ValidateSet('all', 'check', 'prepare', 'thirdparty', 'pjproject', 'app')][string]$Step = 'all',
    [switch]$NoSsl,
    [switch]$BuildSslWin32,
    [switch]$Force,
    [switch]$SkipToolchainCheck
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$steps = Join-Path $PSScriptRoot 'steps'

function Run-Step([string]$script, [string[]]$extra) {
    Write-Host ''
    Write-Host ('-' * 74)
    # NOTE: never name this $args - it is a PowerShell automatic variable.
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $steps $script)) + $extra
    & powershell @psArgs
    if ($LASTEXITCODE -ne 0) { throw "$script failed (exit $LASTEXITCODE)" }
}

$all = ($Step -eq 'all')

# ---------------------------------------------------------------- step 0
if ($all -or $Step -eq 'check') {
    $extra = @()
    if ($NoSsl) { } else { $extra += '-RequireOpenSsl' }
    Run-Step '00-check-toolchain.ps1' $extra
    if ($Step -eq 'check') { exit 0 }
}

# ---------------------------------------------------------------- step 1
if ($all -or $Step -eq 'prepare') {
    $extra = @('-RepoRoot', $repoRoot)
    if ($NoSsl) { $extra += '-NoSsl' }
    Run-Step '01-prepare.ps1' $extra
    if ($Step -eq 'prepare') { exit 0 }
}

# ---------------------------------------------------------------- step 2
if ($all -or $Step -eq 'thirdparty') {
    $extra = @('-RepoRoot', $repoRoot, '-Platform', $Platform, '-Configuration', $Configuration)
    if ($NoSsl) { $extra += '-NoSsl' }
    if ($BuildSslWin32) { $extra += '-BuildSslWin32' }
    if ($Force) { $extra += '-Force' }
    Run-Step '02-thirdparty.ps1' $extra
    if ($Step -eq 'thirdparty') { exit 0 }
}

# ---------------------------------------------------------------- step 3
if ($all -or $Step -eq 'pjproject') {
    # pjproject is only rebuilt for x64; the Win32 application links the
    # prebuilt 32-bit library from third_party\lib
    $extra = @('-RepoRoot', $repoRoot, '-Platform', 'x64')
    if ($Force) { $extra += '-Rebuild' }
    Run-Step '03-pjproject.ps1' $extra
    if ($Step -eq 'pjproject') { exit 0 }
}

# ---------------------------------------------------------------- step 4
if ($all -or $Step -eq 'app') {
    $extra = @('-RepoRoot', $repoRoot, '-Platform', $Platform, '-Configuration', $Configuration)
    if ($Force) { $extra += '-Rebuild' }
    Run-Step '04-app.ps1' $extra
}

Write-Host ''
Write-Host ('=' * 74)
Write-Host 'BUILD FINISHED' -ForegroundColor Green
Write-Host ('=' * 74)
