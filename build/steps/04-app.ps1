<#
.SYNOPSIS
    Step 4 - build the application itself.

.DESCRIPTION
    Compiles microsip.vcxproj for the requested configuration and platform.

    The project file derives its platform toolset from the BuildToolset
    property, so that has to be passed on the command line.

    Note that the Win32 configuration links the *prebuilt* 32-bit pjproject
    library from third_party\lib - rebuilding pjproject for Win32 is out of
    scope, and that library has neither Opus nor TLS. The application handles
    that through the #if defined(_M_X64) guard in pj\config_site.h.

.EXAMPLE
    .\04-app.ps1 -Configuration Debug -Platform x64
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release', 'All')][string]$Configuration = 'All',
    [ValidateSet('x64', 'Win32', 'All')][string]$Platform = 'All',
    [string]$RepoRoot = '',
    [switch]$Rebuild
)

. (Join-Path $PSScriptRoot '_common.ps1')

if (-not $RepoRoot) { $RepoRoot = Get-RepoRoot }
$proj = Join-Path $RepoRoot 'microsip.vcxproj'
if (-not (Test-Path $proj)) { throw "project not found: $proj" }

$cfgs = if ($Configuration -eq 'All') { @('Debug', 'Release') } else { @($Configuration) }
$plats = if ($Platform -eq 'All') { @('x64', 'Win32') } else { @($Platform) }

$toolset = Get-PlatformToolset
Write-Step "building the application (toolset $toolset)"

$target = if ($Rebuild) { 'Rebuild' } else { 'Build' }

foreach ($plat in $plats) {
    foreach ($cfg in $cfgs) {
        # The Win32 application links the *prebuilt* 32-bit pjproject library,
        # and only the Debug flavour of it is vendored. A Release|Win32 build
        # would look for libpjproject-i386-Win32-vc14-Release-Static.lib, which
        # does not exist - skip it with an explanation instead of failing the
        # whole pipeline with a linker error.
        if ($plat -eq 'Win32' -and $cfg -eq 'Release') {
            $rel = Join-Path $RepoRoot 'third_party\lib\libpjproject-i386-Win32-vc14-Release-Static.lib'
            if (-not (Test-Path $rel)) {
                Write-Note 'Win32 | Release skipped: only the Debug flavour of the 32-bit'
                Write-Note '                    pjproject library is vendored. Build pjproject'
                Write-Note '                    for Win32 yourself to get that configuration.'
                continue
            }
        }
        Write-Host "   $plat|$cfg ..."
        Invoke-MsBuild $proj @("/t:$target", "/p:Configuration=$cfg", "/p:Platform=$plat",
            "/p:BuildToolset=$toolset", '/m', '/v:m', '/nologo') "app $plat|$cfg" | Out-Null

        $exe = Join-Path $RepoRoot "$plat\$cfg\microsip.exe"
        if (-not (Test-Path $exe)) { $exe = Join-Path $RepoRoot "$cfg\microsip.exe" }
        if (Test-Path $exe) {
            Write-Ok ("{0,-8} {1,-16} {2,12:N0} bytes" -f $plat, $cfg, (Get-Item $exe).Length)
        } else {
            Write-Note ("{0,-8} {1,-16} (no executable produced)" -f $plat, $cfg)
        }
    }
}

Write-Host ''
Write-Host 'RESULT: application built.' -ForegroundColor Green
