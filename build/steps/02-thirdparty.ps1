<#
.SYNOPSIS
    Step 2 - build every third-party archive the application links against.

.DESCRIPTION
    All of them are built per (platform, configuration) and with the CRT that
    matches the configuration, because a static library carries its CRT
    requirement with it:

        Debug   -> /MTd -> libcmtd
        Release -> /MT  -> libcmt

    Mixing them produces "LINK : warning LNK4098: default library 'libcmt.lib'
    conflicts with other libraries' use" - and, worse, two CRT heaps in one
    process. Upstream never sees this because the archives it ships are never
    pulled into the link (the prebuilt 32-bit pjproject has neither Opus nor
    TLS).

    Produced:
        third_party\lib\<Platform>\chkstk_ms.lib
        third_party\SQLiteCpp\<Platform>\<Configuration>\{sqlite3,SQLiteCpp}.lib
        third_party\bcg729\<Platform>\<Configuration>\bcg729.lib
        third_party\opus\<Platform>\<Configuration>\opus.lib
        third_party\openssl\<Platform>\<Configuration>\lib\{libcrypto,libssl}.lib

.EXAMPLE
    .\02-thirdparty.ps1 -Platform x64 -Configuration Debug
    .\02-thirdparty.ps1 -Platform All -Configuration All
#>
[CmdletBinding()]
param(
    [ValidateSet('x64', 'Win32', 'All')][string]$Platform = 'All',
    [ValidateSet('Debug', 'Release', 'All')][string]$Configuration = 'All',
    [string]$RepoRoot = '',
    [switch]$Force,
    [switch]$NoSsl,
    # The Win32 application links the vendored 32-bit pjproject library, which
    # has no TLS backend - OpenSSL is only built for x64 unless this is set.
    [switch]$BuildSslWin32
)

. (Join-Path $PSScriptRoot '_common.ps1')

if (-not $RepoRoot) { $RepoRoot = Get-RepoRoot }
$work = Get-WorkDir $RepoRoot
$tp = Join-Path $RepoRoot 'third_party'
$stubSrc = Join-Path $RepoRoot 'build\stub\chkstk_ms.c'

$platforms = if ($Platform -eq 'All') { @('x64', 'Win32') } else { @($Platform) }
$cfgs = if ($Configuration -eq 'All') { @('Debug', 'Release') } else { @($Configuration) }

function Crt-Flag([string]$cfg) { if ($cfg -eq 'Debug') { '/MTd' } else { '/MT' } }
function Crt-Msvc([string]$cfg) { if ($cfg -eq 'Debug') { 'MultiThreadedDebug' } else { 'MultiThreaded' } }

# ------------------------------------------------------------ chkstk stub
function Build-ChkstkStub([string]$plat) {
    $outDir = Join-Path $tp "lib\$plat"
    $out = Join-Path $outDir 'chkstk_ms.lib'
    if ((Test-Path $out) -and -not $Force) {
        Write-Ok "chkstk_ms.lib      : $plat (cached)"
        return
    }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $envInfo = Get-MsvcEnv $plat
    $tmp = Join-Path $work "chkstk-$plat"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $obj = Join-Path $tmp 'chkstk_ms.obj'
    # /Zl omits the default library reference, so the stub works for both
    # /MTd and /MT without an LNK4098 conflict
    Invoke-Tool $envInfo.Cl $tmp @('/nologo', '/c', '/Zl', '/O2', '/W0', $stubSrc, "/Fo:$obj") 'chkstk_ms compile' | Out-Null
    Invoke-Tool $envInfo.Lib $tmp @('/nologo', "/OUT:$out", $obj) 'chkstk_ms lib' | Out-Null
    Write-Ok ("chkstk_ms.lib      : {0}" -f $plat)
}

# -------------------------------------------------------------- SQLiteCpp
function Build-SqliteCpp([string]$plat, [string]$cfg) {
    $outDir = Join-Path $tp "SQLiteCpp\$plat\$cfg"
    if ((Test-Path (Join-Path $outDir 'SQLiteCpp.lib')) -and -not $Force) {
        Write-Ok "SQLiteCpp          : $plat/$cfg (cached)"
        return
    }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $src = Join-Path $work 'SQLiteCpp-3.4.0'
    if (-not (Test-Path $src)) { throw 'SQLiteCpp source not found - run 01-prepare.ps1 first' }
    $envInfo = Get-MsvcEnv $plat
    $crt = Crt-Flag $cfg
    $tmp = Join-Path $work "sqlite-$plat-$cfg"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    $sqlite3C = Join-Path $src 'sqlite3\sqlite3.c'
    Invoke-Tool $envInfo.Cl $tmp @('/nologo', '/c', $crt, '/O2', '/W0', '/DSQLITE_THREADSAFE=0',
        $sqlite3C, "/Fo:$tmp\sqlite3.obj") 'sqlite3 compile' | Out-Null
    Invoke-Tool $envInfo.Lib $tmp @('/nologo', "/OUT:$outDir\sqlite3.lib", "$tmp\sqlite3.obj") 'sqlite3 lib' | Out-Null

    $objs = @()
    foreach ($f in Get-ChildItem (Join-Path $src 'src') -Filter *.cpp -File) {
        $obj = Join-Path $tmp ($f.BaseName + '.obj')
        Invoke-Tool $envInfo.Cl $tmp @('/nologo', '/c', $crt, '/O2', '/W0', '/EHsc', '/std:c++14',
            "/I$(Join-Path $src 'include')", "/I$(Join-Path $src 'sqlite3')",
            $f.FullName, "/Fo:$obj") 'SQLiteCpp compile' | Out-Null
        $objs += $obj
    }
    Invoke-Tool $envInfo.Lib $tmp (@('/nologo', "/OUT:$outDir\SQLiteCpp.lib") + $objs) 'SQLiteCpp lib' | Out-Null
    Write-Ok ("SQLiteCpp          : {0}/{1}" -f $plat, $cfg)
}

# ----------------------------------------------------------------- bcg729
function Build-Bcg729([string]$plat, [string]$cfg) {
    $outDir = Join-Path $tp "bcg729\$plat\$cfg"
    if ((Test-Path (Join-Path $outDir 'bcg729.lib')) -and -not $Force) {
        Write-Ok "bcg729            : $plat/$cfg (cached)"
        return
    }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $src = Join-Path $work 'bcg729'
    if (-not (Test-Path $src)) { throw 'bcg729 source not found - run 01-prepare.ps1 first' }
    $envInfo = Get-MsvcEnv $plat
    $crt = Crt-Flag $cfg
    $tmp = Join-Path $work "bcg-$plat-$cfg"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $objs = @()
    foreach ($f in Get-ChildItem (Join-Path $src 'src') -Filter *.c -File) {
        $obj = Join-Path $tmp ($f.BaseName + '.obj')
        Invoke-Tool $envInfo.Cl $tmp @('/nologo', '/c', $crt, '/O2', '/W0',
            "/I$(Join-Path $src 'include')", "/I$(Join-Path $src 'src')",
            $f.FullName, "/Fo:$obj") 'bcg729 compile' | Out-Null
        $objs += $obj
    }
    Invoke-Tool $envInfo.Lib $tmp (@('/nologo', "/OUT:$outDir\bcg729.lib") + $objs) 'bcg729 lib' | Out-Null
    Write-Ok ("bcg729            : {0}/{1}" -f $plat, $cfg)
}

# ------------------------------------------------------------------- opus
function Build-Opus([string]$plat, [string]$cfg) {
    $outDir = Join-Path $tp "opus\$plat\$cfg"
    if ((Test-Path (Join-Path $outDir 'opus.lib')) -and -not $Force) {
        Write-Ok "opus              : $plat/$cfg (cached)"
        return
    }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $src = Join-Path $work 'opus-1.3.1'
    if (-not (Test-Path $src)) { throw 'opus source not found - run 01-prepare.ps1 first' }
    $proj = Join-Path $src 'win32\VS2015\opus.vcxproj'
    if (-not (Test-Path $proj)) { throw "opus.vcxproj not found: $proj" }
    $toolset = Get-PlatformToolset
    Invoke-MsBuild $proj @('/t:Build', "/p:Configuration=$cfg", "/p:Platform=$plat",
        "/p:PlatformToolset=$toolset", "/p:RuntimeLibrary=$(Crt-Msvc $cfg)",
        "/p:OutDir=$outDir\", '/m', '/v:m', '/nologo') 'opus build' | Out-Null
    if (-not (Test-Path (Join-Path $outDir 'opus.lib'))) { throw "opus.lib not produced in $outDir" }
    Write-Ok ("opus              : {0}/{1}" -f $plat, $cfg)
}

# ---------------------------------------------------------------- OpenSSL
function Build-OpenSsl([string]$plat, [string]$cfg) {
    $outDir = Join-Path $tp "openssl\$plat\$cfg\lib"
    if ((Test-Path (Join-Path $outDir 'libssl.lib')) -and -not $Force) {
        Write-Ok "openssl           : $plat/$cfg (cached)"
        return
    }
    $perl = Get-Perl
    if (-not $perl) { throw 'Perl is required to build OpenSSL (winget install StrawberryPerl.StrawberryPerl)' }

    $base = Join-Path $work 'openssl-3.0.15'
    if (-not (Test-Path $base)) { throw 'OpenSSL source not found - run 01-prepare.ps1 first' }
    $src = Join-Path $work "openssl-3.0.15-$plat-$cfg"
    if (-not (Test-Path $src)) {
        Copy-Item $base $src -Recurse -Force
    }

    $envInfo = Get-MsvcEnv $plat
    $crt = Crt-Flag $cfg
    # OpenSSL's valid VC targets are VC-WIN64A (x64) and VC-WIN32 (x86).
    # There is no "VC-WIN32A" - Configure rejects it and prints its target list.
    $vcTarget = if ($plat -eq 'x64') { 'VC-WIN64A' } else { 'VC-WIN32' }
    $extra = @()
    if (-not (Get-Command nasm.exe -ErrorAction SilentlyContinue)) { $extra += 'no-asm' }
    $configureArgs = @($vcTarget, 'no-shared', 'no-module', 'no-tests', 'no-legacy') + $extra + @($crt)

    Invoke-Tool $perl $src (@('Configure') + $configureArgs) 'openssl configure' | Out-Null
    Invoke-Tool $envInfo.NMake $src @('/nologo', 'build_libs') 'openssl nmake' | Out-Null

    # OpenSSL generates several headers (opensslconf.h, configuration.h, …)
    # during Configure - stage the *configured* headers, the pristine archive
    # does not contain them.
    $sslInclude = Join-Path $tp 'openssl\Win32\include\openssl'
    if (Test-Path $sslInclude) { Remove-Item $sslInclude -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $sslInclude | Out-Null
    Copy-Item (Join-Path $src 'include\openssl\*') $sslInclude -Recurse -Force
    Write-Ok ("openssl headers   : {0} files" -f (Get-ChildItem $sslInclude -Recurse -File).Count)

    # OpenSSL 3.x with no-module still ships the providers as separate archives;
    # libcrypto references their symbols. Merging them into libcrypto.lib keeps
    # the single "#pragma comment(lib, "libcrypto")" in pjlib's ssl_sock_ossl.c
    # working no matter where the archive sits on the link line.
    $core = Get-ChildItem $src -Recurse -File -Filter 'libcrypto.lib' | Select-Object -First 1
    $ssl = Get-ChildItem $src -Recurse -File -Filter 'libssl.lib' | Select-Object -First 1
    if (-not $core -or -not $ssl) { throw 'libcrypto/libssl not produced by the OpenSSL build' }
    $providerLibs = @()
    $provDir = Join-Path $src 'providers'
    if (Test-Path $provDir) {
        $providerLibs = @(Get-ChildItem $provDir -File -Filter '*.lib' -ErrorAction SilentlyContinue)
    }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    Copy-Item $ssl.FullName (Join-Path $outDir 'libssl.lib') -Force
    $merged = Join-Path $outDir '_libcrypto_merged.lib'
    $inputs = @($core.FullName) + @($providerLibs | ForEach-Object { $_.FullName })
    Invoke-Tool $envInfo.Lib $src (@('/nologo', "/OUT:$merged") + $inputs) 'openssl merge' | Out-Null
    Move-Item $merged (Join-Path $outDir 'libcrypto.lib') -Force
    Write-Ok ("openssl           : {0}/{1} ({2} provider archives merged)" -f $plat, $cfg, $providerLibs.Count)
}

# ------------------------------------------------------------------- run
foreach ($plat in $platforms) {
    Write-Step "third-party libraries : $plat"
    Build-ChkstkStub $plat
    $skipSsl = $false
    if (-not $NoSsl -and $plat -ne 'x64' -and -not $BuildSslWin32) {
        $skipSsl = $true
        Write-Note 'openssl           : not built for this platform (see below)'
    }
    foreach ($cfg in $cfgs) {
        Build-SqliteCpp $plat $cfg
        Build-Bcg729 $plat $cfg
        Build-Opus $plat $cfg
        if (-not $NoSsl -and -not $skipSsl) { Build-OpenSsl $plat $cfg }
    }
    if ($skipSsl) {
        Write-Host ''
        Write-Host '    The Win32 application links the vendored 32-bit pjproject library,'
        Write-Host '    which was compiled WITHOUT a TLS backend: it exports neither'
        Write-Host '    pj_ssl_sock_start_connect nor any OpenSSL symbol. OpenSSL is'
        Write-Host '    therefore never referenced at link time and building it would'
        Write-Host '    cost ~20 minutes for archives nobody links. Use -BuildSslWin32'
        Write-Host '    to build it anyway.'
    }
}

Write-Host ''
Write-Host 'RESULT: third-party libraries ready.' -ForegroundColor Green
Get-ChildItem $tp -Recurse -File -Filter '*.lib' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\src\\' } |
    ForEach-Object { "    {0,12:N0}  {1}" -f $_.Length, $_.FullName.Substring($tp.Length + 1) }
