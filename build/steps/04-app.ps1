<#
.SYNOPSIS
    Step 4 - build the application itself.

.DESCRIPTION
    Compiles microsip.vcxproj for the requested configuration and platform.

    The project file derives its platform toolset from the BuildToolset
    property, so that has to be passed on the command line.

    Both platforms link the pjproject library that build\steps\03-pjproject.ps1
    builds - there is no vendored prebuilt library any more. The Win32 build
    sees PJ_HAS_SSL_SOCK 0 and PJMEDIA_HAS_OPUS_CODEC 0, because OpenSSL is
    only built for x64; the #if defined(_M_X64) guard in pj\config_site.h
    keeps the application and the library it links against in sync.

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
