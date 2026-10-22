<#
.SYNOPSIS
    Verify whether a MicroSIP pjproject dependency is stock upstream or locally patched.

.DESCRIPTION
    Answers three questions with byte-level evidence instead of guesswork:

      1. Do the pjproject headers in the dependency tree match an upstream release?
      2. Do the modules inside the prebuilt static library correspond to upstream
         source files (i.e. is anything author-specific compiled in)?
      3. Does the library export any symbol that upstream does not have?

    Implementation notes:
      * Header comparison keys files by "parent-dir-name/file-name", which maps a
        flattened include tree (third_party/pjsip/sip.h) onto the upstream layout
        (pjsip/include/pjsip/sip.h) without a hardcoded directory table.
      * Everything is SHA-256 based. Do NOT use `git diff --no-index` for this:
        it walks the whole tree including third_party codecs and times out.

.PARAMETER UpstreamRoot
    Extracted upstream pjproject tree, e.g. ...\pjproject-2.14.1

.PARAMETER UpstreamRoot2
    Optional second upstream tree, used to distinguish "upstream changed later"
    from "locally patched".

.PARAMETER HeaderTree
    Optional flattened pjproject include tree, e.g. <repo>\third_party

.PARAMETER AuthorTree
    Optional full source tree to scan for locally patched files, e.g. a checkout of
    github.com/pythonist77/microsip

.PARAMETER Lib
    Optional prebuilt static library to inspect, e.g. libpjproject-i386-Win32-vc14-Debug-Static.lib

.PARAMETER Dumpbin
    Optional path to dumpbin.exe. Auto-detected from Visual Studio if omitted.

.EXAMPLE
    .\verify-pjproject-provenance.ps1 `
        -UpstreamRoot  D:\github\_tmp_upstream_pj\pjproject-2.14.1 `
        -HeaderTree    .\third_party `
        -Lib           .\third_party\lib\libpjproject-i386-Win32-vc14-Debug-Static.lib
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UpstreamRoot,
    [string]$UpstreamRoot2,
    [string]$HeaderTree,
    [string]$AuthorTree,
    [string]$Lib,
    [string]$Dumpbin
)

$ErrorActionPreference = 'Stop'

# IMPORTANT: never use `Get-ChildItem -Recurse -Include` on a literal path.
# Without a trailing \* the -Include filter behaves inconsistently and silently
# under-reports files. Filter on Extension instead - this bug produced wrong
# numbers during the original investigation.
function Get-Sources([string]$root, [string[]]$exts) {
    if (-not (Test-Path $root)) { return @() }
    Get-ChildItem $root -Recurse -File | Where-Object { $exts -contains $_.Extension }
}

function Get-Key([string]$path, [string]$root) {
    # "parent-dir-name/file-name" -> layout independent identity
    $rel = $path.Substring($root.Length + 1)
    $parts = $rel -split '\\'
    if ($parts.Count -lt 2) { return $parts[-1] }
    return ($parts[-2] + '/' + $parts[-1])
}

function Get-HashIndex([string]$root, [string[]]$exts) {
    $idx = @{}
    if (-not (Test-Path $root)) { return $idx }
    foreach ($f in (Get-Sources $root $exts)) {
        $h = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
        if (-not $idx.ContainsKey($h)) { $idx[$h] = @() }
        $idx[$h] += $f.Name
    }
    return $idx
}

function Get-HeaderKeyIndex([string]$root) {
    # Two views of the upstream headers:
    #   'dir/file' -> hashes   (nested upstream layout, e.g. pjsip/include/pjsip/sip.h)
    #   'file'     -> hashes   (flat convenience headers, e.g. pjlib/include/pjlib.h)
    $idx = @{ 'dir' = @{}; 'name' = @{} }
    if (-not (Test-Path $root)) { return $idx }
    foreach ($f in (Get-Sources $root @('.h', '.hpp'))) {
        $h = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
        $k = Get-Key $f.FullName $root
        if (-not $idx['dir'].ContainsKey($k)) { $idx['dir'][$k] = @() }
        $idx['dir'][$k] += ,$h
        $n = $f.Name
        if (-not $idx['name'].ContainsKey($n)) { $idx['name'][$n] = @() }
        $idx['name'][$n] += ,$h
    }
    return $idx
}

function Write-Section([string]$title) {
    ''
    "=== $title ==="
}

# ---------------------------------------------------------------- 1. headers
if ($HeaderTree) {
    Write-Section "1. Headers vs upstream $(Split-Path $UpstreamRoot -Leaf)"
    $up = Get-HeaderKeyIndex $UpstreamRoot
    $same = 0; $diff = @(); $miss = @(); $generated = @()
    foreach ($f in (Get-Sources $HeaderTree @('.h', '.hpp'))) {
        $rel = $f.FullName.Substring($HeaderTree.Length + 1)
        $k = Get-Key $f.FullName $HeaderTree
        $h = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
        $hashes = $null
        if ($up['dir'].ContainsKey($k)) { $hashes = $up['dir'][$k] }
        elseif (($rel -notmatch '\\') -and $up['name'].ContainsKey($f.Name)) { $hashes = $up['name'][$f.Name] }
        if (-not $hashes) {
            # a one-line "#include <...>" wrapper is a flattening artifact, not a pjproject file
            $txt = (Get-Content $f.FullName -Raw)
            if ($txt -match '^\s*#include\s+[<"][^>"]+[>"]\s*$') { $generated += $k } else { $miss += $k }
            continue
        }
        if ($hashes -contains $h) { $same++ } else { $diff += $k }
    }
    "identical to upstream : $same"
    "differing              : $($diff.Count)"
    $diff | ForEach-Object { "    DIFF $_" }
    "no upstream counterpart (pjproject files) : $($miss.Count)"
    $miss | ForEach-Object { "    MISS $_" }
    "flattening wrapper headers (ignored) : $($generated.Count)"

    # config_site.h is the one file that legitimately differs - show the delta
    $csPath = Join-Path $HeaderTree 'pj\config_site.h'
    $sample = Get-ChildItem $UpstreamRoot -Recurse -File -Filter 'config_site_sample.h' | Select-Object -First 1
    if ((Test-Path $csPath) -and $sample) {
        Write-Section "1b. config_site.h vs upstream config_site_sample.h"
        $a = Get-Content $csPath
        $b = Get-Content $sample.FullName
        $d = Compare-Object $b $a
        if (-not $d) { "IDENTICAL to upstream sample" }
        else { $d | ForEach-Object { "    {0} {1}" -f $_.SideIndicator, $_.InputObject.Trim() } }
    }
}

# ------------------------------------------------- 2. locally patched files
if ($AuthorTree) {
    Write-Section "2. Author tree vs upstream (which files are NOT upstream?)"
    $baselines = @($UpstreamRoot)
    if ($UpstreamRoot2) { $baselines += $UpstreamRoot2 }
    $idx = @{}
    foreach ($b in $baselines) {
        foreach ($h in (Get-HashIndex $b @('.c')).Keys) { $idx[$h] = $true }
        foreach ($h in (Get-HashIndex $b @('.h')).Keys) { $idx[$h] = $true }
    }
    $cand = @()
    foreach ($f in (Get-Sources $AuthorTree @('.c', '.h'))) {
        $h = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
        if (-not $idx.ContainsKey($h)) { $cand += $f.FullName.Substring($AuthorTree.Length + 1) }
    }
    "author .c/.h files scanned : $((Get-Sources $AuthorTree @('.c','.h')).Count)"
    "baselines compared : $($baselines -join ' , ')"
    "files matching NO baseline (real patch candidates) : $($cand.Count)"
    $cand | Sort-Object | ForEach-Object { "    $_" }
    '  Note: files under MicroSIP-*/ and pjsip-apps/ are the app and upstream sample apps,'
    '  not pjproject core - ignore them when judging "is this a private fork?".'
}

# ------------------------------------------------------------- 3. the library
if ($Lib) {
    Write-Section "3. Static library: $($Lib)"
    if (-not (Test-Path $Lib)) { "  library not found"; }
    else {
        # 3a. module names vs upstream source file basenames
        $libExe = $Dumpbin
        if (-not $libExe) {
            $libExe = (Get-ChildItem 'C:\Program Files\Microsoft Visual Studio' -Recurse -Filter 'lib.exe' -ErrorAction SilentlyContinue |
                       Where-Object { $_.FullName -like '*Hostx64\x86*' } | Select-Object -First 1).FullName
        }
        $upBase = @{}
        foreach ($f in (Get-Sources $UpstreamRoot @('.c', '.cpp'))) { $upBase[$f.BaseName.ToLower()] = $true }
        $mods = @()
        if ($libExe -and (Test-Path $libExe)) {
            $tmp = [System.IO.Path]::GetTempFileName()
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $libExe
            $psi.Arguments = "/nologo /list `"$Lib`""
            $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $p = [System.Diagnostics.Process]::Start($psi)
            $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
            $mods = ($out -split "`r?`n") | ForEach-Object { ($_ -split '\\')[-1] } |
                    Where-Object { $_ -like '*.obj' } | ForEach-Object { $_ -replace '\.obj$','' } | Sort-Object -Unique
        }
        "distinct modules : $($mods.Count)"
        $orphan = @($mods | Where-Object { -not $upBase.ContainsKey($_.ToLower()) })
        "modules with NO same-named upstream .c : $($orphan.Count)"
        $orphan | ForEach-Object { "    $_" }
        '  Note: upstream ships libyuv as HEADERS only (third_party/yuv); its sources are'
        '  fetched at build time, so libyuv modules (scale_*, convert_*, rotate_*, row_*,'
        '  compare_*, mjpeg_*, video_common, cpu_*) legitimately have no .c in the zip.'

        # 3b. exported symbols vs upstream
        $dump = $Dumpbin
        if (-not $dump) {
            $dump = (Get-ChildItem 'C:\Program Files\Microsoft Visual Studio' -Recurse -Filter 'dumpbin.exe' -ErrorAction SilentlyContinue |
                     Where-Object { $_.FullName -like '*Hostx64\x86*' } | Select-Object -First 1).FullName
        }
        if ($dump -and (Test-Path $dump)) {
            $api = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($f in (Get-Sources $UpstreamRoot @('.h', '.hpp'))) {
                $txt = Get-Content $f.FullName -Raw
                [regex]::Matches($txt, '\b([A-Za-z_][A-Za-z0-9_]*)\b') | ForEach-Object {
                    $v = $_.Value
                    if ($v -match '^[pP][jJ]') { [void]$api.Add($v) }
                }
            }
            $symFile = [System.IO.Path]::GetTempFileName()
            $psi2 = New-Object System.Diagnostics.ProcessStartInfo
            $psi2.FileName = $dump
            $psi2.Arguments = "/nologo /symbols `"$Lib`""
            $psi2.RedirectStandardOutput = $true; $psi2.RedirectStandardError = $true
            $psi2.UseShellExecute = $false
            $p2 = [System.Diagnostics.Process]::Start($psi2)
            $out2 = $p2.StandardOutput.ReadToEnd(); $p2.WaitForExit()
            Set-Content -Path $symFile -Value $out2 -Encoding utf8

            $syms = New-Object 'System.Collections.Generic.HashSet[string]'
            Get-Content $symFile | ForEach-Object {
                if ($_ -match 'External\s*\|\s*(\S+)') {
                    $n = $matches[1]
                    # MSVC prefixes C symbols with '_' on x86 but NOT on x64
                    if ($n -match '^_*(pj[A-Za-z0-9_]+)$') { [void]$syms.Add($matches[1]) }
                }
            }
            "exported pj* C symbols : $($syms.Count)"
            $notInHeaders = $syms | Where-Object { -not $api.Contains($_) } | Sort-Object
            "not declared in upstream headers : $($notInHeaders.Count)"
            # those may still be internal symbols defined in upstream .c files
            $upSources = (Get-Sources $UpstreamRoot @('.c', '.cpp')) | ForEach-Object { $_.FullName }
            $trulyExtra = @()
            foreach ($s in $notInHeaders) {
                $hit = Select-String -Path $upSources -Pattern "\b$([regex]::Escape($s))\b" -List -ErrorAction SilentlyContinue
                if (-not $hit) { $trulyExtra += $s }
            }
            "NOT found anywhere in upstream : $($trulyExtra.Count)  <-- these would be author-only APIs"
            $trulyExtra | ForEach-Object { "    $_" }
            if ($notInHeaders.Count -gt $trulyExtra.Count) {
                "  (the other $($notInHeaders.Count - $trulyExtra.Count) are internal upstream symbols living only in .c files)"
            }
        }
    }
}

''
'Done.'
