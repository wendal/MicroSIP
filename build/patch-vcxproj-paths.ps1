<#
.SYNOPSIS
    One-off migration: point microsip.vcxproj at the in-repository third_party
    tree instead of a sibling directory outside the repository.

.DESCRIPTION
    The released project file addresses its dependencies through "..", because
    in the author's layout the dependency tree sits next to the application
    folder. For a self-contained repository the paths have to be relative to
    the project directory itself:

        ..\third_party\...      ->  third_party\...
        ..\lib\                 ->  third_party\lib\$(Platform)\ + third_party\lib\

    The script rewrites AdditionalIncludeDirectories and
    AdditionalLibraryDirectories in every configuration and keeps the
    per-architecture Windows SDK path intact.

    Library search path after the migration (order matters, see BUILD.md 11.3):
        third_party\lib\$(Platform)\            chkstk_ms stub, generated
        third_party\lib\                        prebuilt 32-bit pjproject
        third_party\openssl\$(Platform)\$(Configuration)\lib\
        third_party\opus\$(Platform)\$(Configuration)\
        third_party\bcg729\$(Platform)\$(Configuration)\
        third_party\SQLiteCpp\$(Platform)\$(Configuration)\

    Note that the directory that holds the *shared* third_party\lib must not
    contain architecture specific archives: it is searched before the
    per-platform folders, so a 32-bit opus.lib sitting there would win over
    the 64-bit one and the x64 build would fail with unresolved opus_* symbols.

    NOTE: the file is UTF-8 with BOM and CRLF; the script works on the raw
    bytes so that neither is disturbed.

.EXAMPLE
    .\patch-vcxproj-paths.ps1
#>
[CmdletBinding()]
param(
    [string]$Project = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Project) { $Project = Join-Path (Split-Path $PSScriptRoot -Parent) 'microsip.vcxproj' }
if (-not (Test-Path $Project)) { throw "project not found: $Project" }

$bytes = [System.IO.File]::ReadAllBytes($Project)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)

# The project imports the upstream pjproject VS configuration, which used to
# live in a sibling directory. It is vendored in build\vs\ now.
$text = $text.Replace('<Import Project="..\build\vs\pjproject-vs14-common-config.props" />',
                      '<Import Project="build\vs\pjproject-vs14-common-config.props" />')

$newInclude = 'lib;lib\jsoncpp\json;third_party;third_party\SQLiteCpp;third_party\opus\include;' +
              'third_party\bcg729\include;third_party\openssl\Win32\include;.;' +
              'c:\Program Files (x86)\Windows Kits\10\Include\10.0.19041.0\winrt;%(AdditionalIncludeDirectories)'

$newLibPrefix = 'third_party\lib\$(Platform)\;third_party\lib\;' +
                'third_party\openssl\$(Platform)\$(Configuration)\lib\;' +
                'third_party\opus\$(Platform)\$(Configuration)\\;' +
                'third_party\bcg729\$(Platform)\$(Configuration)\;' +
                'third_party\SQLiteCpp\$(Platform)\$(Configuration)\;'

# ---- include directories ------------------------------------------------
$incCount = 0
$text = [regex]::Replace($text, '<AdditionalIncludeDirectories>[^<]*</AdditionalIncludeDirectories>', {
    param($m)
    $script:incCount++
    "<AdditionalIncludeDirectories>$newInclude</AdditionalIncludeDirectories>"
})

# ---- library directories ------------------------------------------------
$libCount = 0
$text = [regex]::Replace($text, '<AdditionalLibraryDirectories>([^<]*)</AdditionalLibraryDirectories>', {
    param($m)
    $script:libCount++
    # keep the per-architecture Windows SDK path of this configuration
    $sdk = '$(WindowsSDK_LibraryPath_x64)'
    if ($m.Groups[1].Value -match '\$\(WindowsSDK_LibraryPath_(\w+)\)') { $sdk = "`$(WindowsSDK_LibraryPath_$($Matches[1]))" }
    "<AdditionalLibraryDirectories>$newLibPrefix$sdk;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>"
})

[System.IO.File]::WriteAllBytes($Project, [System.Text.Encoding]::UTF8.GetBytes($text))

[xml]$null = Get-Content $Project -Raw
Write-Host "patched include directories : $incCount"
Write-Host "patched library directories : $libCount"
Write-Host "ok                          : $Project is still valid XML"
Write-Host ''
Write-Host 'resulting settings:'
Select-String -Path $Project -Pattern 'AdditionalIncludeDirectories|AdditionalLibraryDirectories' |
    Select-Object -First 2 | ForEach-Object { '   ' + $_.Line.Trim() }
