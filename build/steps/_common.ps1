<#
    Shared helpers for the build pipeline.

    Dot-source it:  . (Join-Path $PSScriptRoot '_common.ps1')
#>

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    # <repo>\build\steps\_common.ps1  ->  <repo>
    return (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
}

function Get-WorkDir([string]$RepoRoot) { return (Join-Path $RepoRoot 'build\work') }

function Write-Step([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "   [ok]   $Text" }
function Write-Note([string]$Text) { Write-Host "   [note] $Text" }
function Write-Miss([string]$Text) { Write-Host "   [MISS] $Text" -ForegroundColor Yellow }

# ---------------------------------------------------------------- MSVC env
function Get-MsvcEnv([string]$arch) {
    $vsRoot = $null
    $vsVersion = $null
    foreach ($v in @('18', '2022')) {
        $c = "C:\Program Files\Microsoft Visual Studio\$v"
        if (Test-Path $c) { $vsRoot = $c; $vsVersion = $v; break }
    }
    if (-not $vsRoot) { throw 'Visual Studio not found' }

    $hostArch = if ($arch -eq 'x64') { 'x64' } else { 'x86' }
    $clExe = Get-ChildItem "$vsRoot\*\VC\Tools\MSVC\*\bin\Hostx64\$hostArch\cl.exe" -File -ErrorAction SilentlyContinue |
             Sort-Object { [version]($_.FullName -split 'MSVC\\')[1].Split('\')[0] } -Descending |
             Select-Object -First 1
    if (-not $clExe) { throw "cl.exe not found for $arch under $vsRoot" }
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
    $env:Path = (Join-Path $vcRoot "bin\Hostx64\$hostArch") + ';' +
                (Join-Path $sdkRoot "bin\$($sdkVer.Name)\$libArch") + ';' + $env:Path

    return [pscustomobject]@{
        Arch       = $arch
        VsRoot     = $vsRoot
        VsVersion  = $vsVersion
        VcRoot     = $vcRoot
        Cl         = $clExe.FullName
        Lib        = (Join-Path $vcRoot "bin\Hostx64\$hostArch\lib.exe")
        NMake      = (Join-Path $vcRoot "bin\Hostx64\$hostArch\nmake.exe")
        SdkVersion = $sdkVer.Name
    }
}

function Get-MsBuild {
    foreach ($vs in @('18', '2022')) {
        $c = "C:\Program Files\Microsoft Visual Studio\$vs"
        if (-not (Test-Path $c)) { continue }
        $m = Get-ChildItem $c -Recurse -Filter 'MSBuild.exe' -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -like '*MSBuild\Current\Bin*' } | Select-Object -First 1
        if ($m) { return $m.FullName }
    }
    return $null
}

function Get-Perl {
    # OpenSSL's Configure needs a perl interpreter. Look in the usual install
    # locations first, then fall back to whatever is on PATH.
    foreach ($c in @(
        'C:\Strawberry\perl\bin\perl.exe',
        'C:\Perl64\bin\perl.exe',
        'C:\Program Files\Git\usr\bin\perl.exe',
        (Get-Command perl.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    )) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

function Get-PlatformToolset {
    # The toolset names live one level deeper than the MSBuild version folders:
    #   ...\MSBuild\Microsoft\VC\v180\Platforms\Win32\PlatformToolsets\v145
    # (VS 2026 = MSBuild "v180" folder, toolset "v145").
    $cands = @()
    foreach ($v in @('18', '2022')) {
        $p = "C:\Program Files\Microsoft Visual Studio\$v"
        if (-not (Test-Path $p)) { continue }
        # the * skips the edition folder (Community / Professional / …)
        $cands += Get-ChildItem "$p\*\MSBuild\Microsoft\VC\v*\Platforms\Win32\PlatformToolsets" -Directory -ErrorAction SilentlyContinue |
                  ForEach-Object { Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue } |
                  Select-Object -ExpandProperty Name
    }
    if (-not $cands) { return 'v143' }
    # prefer the newest v14x toolset
    $v14x = $cands | Where-Object { $_ -match '^v14\d$' } | Sort-Object { [int]($_ -replace '\D', '') }
    if ($v14x) { return $v14x[-1] }
    return ($cands | Sort-Object { [int]($_ -replace '\D', '') })[-1]
}

# --------------------------------------------------------------- execution
function Invoke-Tool([string]$exe, [string]$workDir, [string[]]$toolArgs, [string]$what = 'tool') {
    # NOTE: never name a parameter $args - it is a PowerShell automatic variable.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ($toolArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    $psi.WorkingDirectory = $workDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $out = $outTask.Result + $errTask.Result
    if ($p.ExitCode -ne 0) {
        throw "$what failed (exit $($p.ExitCode))`n$($out -split "`r?`n" | Select-Object -Last 25 | Out-String)"
    }
    return $out
}

function Invoke-MsBuild([string]$project, [string[]]$msbuildArgs, [string]$what = 'msbuild') {
    $msbuild = Get-MsBuild
    if (-not $msbuild) { throw 'MSBuild.exe not found' }
    $out = Invoke-Tool $msbuild (Split-Path $project -Parent) (@($project) + $msbuildArgs) $what
    return $out
}

# ------------------------------------------------------------------ helpers
function Expand-ArchiveOnce([string]$zip, [string]$dest, [string]$marker) {
    if (Test-Path (Join-Path $dest $marker)) { return $false }
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
    return $true
}
