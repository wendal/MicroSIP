<#
.SYNOPSIS
    Step 0 - check that everything the build needs is installed.

.DESCRIPTION
    Prints one line per requirement with [ok] or [MISS]. A missing optional
    tool is downgraded to a note; a missing required tool ends the script with
    the exact installation hint.

    Required:
        Visual Studio 2022 / 2026 with the "Desktop development with C++" workload
            -> MSBuild.exe, cl.exe, lib.exe, nmake.exe
        Windows SDK 10
        Strawberry Perl            (only needed to build OpenSSL)

    Optional:
        NASM                       (OpenSSL uses no-asm when it is missing)
        git-lfs                    (only needed when cloning, to pull the
                                    vendored archives in third_party\src)

.EXAMPLE
    .\00-check-toolchain.ps1
    .\00-check-toolchain.ps1 -RequireOpenSsl
#>
[CmdletBinding()]
param(
    [switch]$RequireOpenSsl,
    [switch]$RequireLfs
)

. (Join-Path $PSScriptRoot '_common.ps1')

$missing = @()

Write-Step 'toolchain check'

# ------------------------------------------------------------ Visual Studio
$msbuild = Get-MsBuild
if ($msbuild) {
    Write-Ok "MSBuild            : $msbuild"
} else {
    Write-Miss 'MSBuild            : NOT FOUND'
    $missing += @'
Visual Studio with the C++ workload is required.
  winget install --id Microsoft.VisualStudio.2022.Community
  (or install "Desktop development with C++" in the Visual Studio Installer)
'@
}

$envInfo = $null
foreach ($arch in @('x64', 'x86')) {
    try {
        $e = Get-MsvcEnv $arch
        if (-not $envInfo) { $envInfo = $e }
        Write-Ok ("MSVC {0,-4}          : {1}" -f $arch, $e.Cl)
    } catch {
        Write-Miss ("MSVC {0,-4}          : {1}" -f $arch, $_.Exception.Message)
    }
}
if (-not $envInfo) {
    $missing += 'The MSVC compiler toolset (cl.exe) was not found.'
}

if ($envInfo) {
    Write-Ok ("Windows SDK        : {0}" -f $envInfo.SdkVersion)
    Write-Ok ("platform toolset   : {0}" -f (Get-PlatformToolset))
} else {
    Write-Miss 'Windows SDK        : NOT FOUND'
    $missing += 'The Windows 10 SDK is required (it ships with Visual Studio).'
}

# ---------------------------------------------------------------------- perl
$perl = Get-Perl
if ($perl) {
    $ver = (& $perl -e 'print $^V' 2>$null)
    Write-Ok "Perl               : $perl ($ver)"
} else {
    Write-Miss 'Perl               : NOT FOUND'
    if ($RequireOpenSsl) {
        $missing += @'
Perl is required to build OpenSSL.
  winget install --id StrawberryPerl.StrawberryPerl
'@
    } else {
        Write-Note 'Perl is required to build OpenSSL (PJ_HAS_SSL_SOCK).'
    }
}

# ---------------------------------------------------------------------- nasm
$nasm = (Get-Command nasm.exe -ErrorAction SilentlyContinue).Source
if ($nasm) {
    Write-Ok "NASM               : $nasm"
} else {
    Write-Note 'NASM               : not installed - OpenSSL will be built with no-asm'
}

# ------------------------------------------------------------------- git-lfs
$lfs = $null
try { $lfs = (& git lfs version 2>$null) } catch { }
if ($lfs) {
    Write-Ok "git-lfs            : $lfs"
} else {
    Write-Miss 'git-lfs            : NOT FOUND'
    if ($RequireLfs) {
        $missing += @'
git-lfs is required to fetch the vendored archives in third_party\src.
  winget install --id GitHub.GitLFS
'@
    } else {
        Write-Note 'git-lfs is only needed when cloning (to pull third_party\src).'
    }
}

# -------------------------------------------------------------- git itself
$git = (Get-Command git.exe -ErrorAction SilentlyContinue).Source
if ($git) { Write-Ok "git                : $git" } else { Write-Note 'git                : not found (only needed for the repository itself)' }

# ------------------------------------------------------------------- summary
Write-Host ''
if ($missing.Count -eq 0) {
    Write-Host 'RESULT: all required tools are present.' -ForegroundColor Green
    exit 0
}

Write-Host 'RESULT: the following is missing:' -ForegroundColor Yellow
Write-Host ''
foreach ($m in $missing) { Write-Host $m; Write-Host '' }
exit 1
