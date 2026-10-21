# Building MicroSIP 3.22.16 from source

The official release archive (`MicroSIP-3.22.16-src.7z`, downloadable from
<https://www.microsip.org/source>) contains **only the application sources**.
`microsip.vcxproj` expects to sit next to a full dependency tree:

```
<build-root>/
├─ build/vs/pjproject-vs14-common-config.props   (imported by microsip.vcxproj)
├─ third_party/…                                 (pjsip headers, SQLiteCpp, libs)
├─ lib/                                          (prebuilt static libs)
└─ MicroSIP-3.22.16-src/                         (this repository)
```

Upstream ships none of it — the project page states:

> MicroSIP relies on third-party libraries that are **not included in this
> repository**.

This document records how the tree was reconstructed and how to rebuild it.

---

## 1. Layout used for the working build

The dependency tree lives **outside** this repository, in `D:\github\microsip-build`:

```
D:\github\microsip-build\
├─ build\vs\pjproject-vs14-common-config.props
├─ lib\            libpjproject-i386-Win32-vc14-Debug-Static.lib, opus.lib,
│                   bcg729.lib, chkstk_ms.lib
├─ third_party\    pjsip headers (pj\, pjsip\, pjmedia\, pjnath\, pjlib-util\,
│                   pjsua-lib\, …), SQLiteCpp\, lib\, bcg729\
└─ MicroSIP-3.22.16-src\   → directory junction to this repository
```

The junction keeps the git repository and the build tree in sync without
copying sources:

```powershell
New-Item -ItemType Junction `
  -Path "D:\github\microsip-build\MicroSIP-3.22.16-src" `
  -Target "D:\github\MicroSIP-3.22.16-src"
```

---

## 2. Where every dependency came from

| Dependency | Source |
|---|---|
| `build/vs/pjproject-vs14-common-config.props` | **Reconstructed by hand** — the original is author-private. See §3. |
| pjsip headers (2.14.1) + `libpjproject-i386-Win32-vc14-Debug-Static.lib` + `opus.lib` | `github.com/pythonist77/microsip` — the author's pjproject fork; the sibling repo `guilhermejansen/MicroSIP-Com-Deps` (branch `master`) carries a ready-made `third_party/` tree with those headers and the prebuilt `libpjproject-…-Debug-Static.lib` + `opus.lib`. |
| `bcg729.lib` | Built from source: `github.com/Lekensteyn/bcg729` (ITU G.729 Annex A/B codec). |
| `SQLiteCpp.lib`, `sqlite3.lib` | Built from source: `github.com/SRombauts/SQLiteCpp` tag **3.4.0** (bundles sqlite3 3.53.4). |
| `chkstk_ms.lib` | **Stub.** The name is an ARM64-only library; it does not exist for x86 in any Windows SDK. See §5. |

Downloads were made through the `gh-proxy.com` mirror (`github.com` is not
directly reachable from this network; `codeload.github.com` is).

```powershell
curl.exe -sSL -o deps.zip "https://gh-proxy.com/https://github.com/guilhermejansen/MicroSIP-Com-Deps/archive/refs/heads/master.zip"
curl.exe -sSL -o sqlitecpp.zip "https://codeload.github.com/SRombauts/SQLiteCpp/zip/refs/tags/3.4.0"
curl.exe -sSL -o bcg729.zip   "https://codeload.github.com/Lekensteyn/bcg729/zip/refs/heads/master"
```

---

## 3. `build/vs/pjproject-vs14-common-config.props`

The original file is author-private. It only has to supply three things the
project file consumes:

* `$(BuildToolset)` — the original says `v140` (VS2015), which no longer
  ships. Use `v143` (VS2022) or `v145` (VS2026).
* `$(PlatformVersion)` — the Windows SDK version.
* the `PJ_WIN32` / `PJ_M_I386` / `PJ_M_X86_64` macros, which must match the
  configuration the prebuilt pjsip library was compiled with.

```xml
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <BuildToolset Condition="'$(BuildToolset)'=='' and $(MSBuildExtensionsPath.Contains('\18\'))">v145</BuildToolset>
    <BuildToolset Condition="'$(BuildToolset)'==''">v143</BuildToolset>
    <PlatformVersion Condition="'$(PlatformVersion)'==''">10.0.26100.0</PlatformVersion>
  </PropertyGroup>
  <ItemDefinitionGroup>
    <ClCompile>
      <PreprocessorDefinitions Condition="'$(Platform)'=='Win32'">PJ_WIN32=1;PJ_M_I386=1;%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <PreprocessorDefinitions Condition="'$(Platform)'=='x64'">PJ_WIN64=1;PJ_M_X86_64=1;%(PreprocessorDefinitions)</PreprocessorDefinitions>
    </ClCompile>
  </ItemDefinitionGroup>
</Project>
```

`third_party/` doubles as a single include root: `pj/config.h`, `pjlib.h`,
`pjsip/sip.h` and `pjsua-lib/pjsua.h` all resolve from it, so no extra include
directories are needed.

---

## 4. Building the third-party libraries

All of them must be compiled with the **static debug CRT (`/MTd`)** to match
`RuntimeLibrary=MultiThreadedDebug` in `microsip.vcxproj` and the
`LIBCMTD` directive inside the prebuilt pjsip library. See §5.

```bat
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" x86

rem --- sqlite3 ---
cl /nologo /c /MTd /O2 /W0 /DSQLITE_THREADSAFE=0 <SQLiteCpp>\sqlite3\sqlite3.c /Fo:sqlite3.obj
lib /nologo /OUT:sqlite3.lib sqlite3.obj

rem --- SQLiteCpp (C++14 is enough for 3.x) ---
cl /nologo /c /MTd /O2 /W0 /EHsc /std:c++14 /I<SQLiteCpp>\include /I<third_party\SQLiteCpp> <SQLiteCpp>\src\*.cpp
lib /nologo /OUT:SQLiteCpp.lib Backup.obj Column.obj Database.obj Exception.obj Savepoint.obj Statement.obj Transaction.obj

rem --- bcg729 ---
cl /nologo /c /MTd /O2 /W0 /I<bcg729>\include /I<bcg729>\src <bcg729>\src\*.c
lib /nologo /OUT:bcg729.lib *.obj
```

Install layout expected by the project file:

```
third_party\SQLiteCpp\SQLiteCpp\*.h        <- include\SQLiteCpp\*.h
third_party\SQLiteCpp\sqlite3.h
third_party\SQLiteCpp\Win32\Debug\SQLiteCpp.lib
third_party\SQLiteCpp\Win32\Debug\sqlite3.lib
third_party\bcg729\Win32\bcg729.lib
lib\*.lib
```

---

## 5. Two traps in the released project file

### `chkstk_ms.lib` does not exist for x86/x64

`microsip.vcxproj` lists `chkstk_ms.lib` in **every** configuration. That
library is ARM64-only and ships in no Windows SDK for x86:

```
LINK : fatal error LNK1104: 无法打开文件"chkstk_ms.lib"
```

For x86/x64 the stack-probe support comes from `chkstk.lib`, which the compiler
links automatically. The working build supplies an empty placeholder library:

```bat
cl /nologo /c /MTd stub.c     :: any translation unit
lib /nologo /OUT:chkstk_ms.lib stub.obj
```

### CRT mismatch produces misleading `LNK2019`

The prebuilt pjsip library carries `/DEFAULTLIB:LIBCMTD` (static debug CRT)
and `opus.lib` carries `/DEFAULTLIB:LIBCMT` (static **release** CRT). The
application itself is built with the static CRT (`RuntimeLibrary`
= `MultiThreadedDebug` / `MultiThreaded`), so locally built libraries must use
`/MTd` too. If they are built with `/MDd`, the link fails with errors that
point at the wrong thing:

```
LINK : warning LNK4098: 默认库"msvcrtd.lib"与其他库的使用冲突
msvcrtd.lib(chandler4gs.obj) : error LNK2019: 无法解析的外部符号 __except_handler4_common
sqlite3.lib(sqlite3.obj)     : error LNK2019: 无法解析的外部符号 __imp__strspn
```

`__except_handler4_common` and `__imp__strspn` are perfectly normal symbols —
they are missing only because the dynamic CRT was pulled in alongside the
static one.

---

## 6. Building the application

```powershell
& "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe" `
   microsip.vcxproj /t:Build /p:Configuration=Debug /p:Platform=Win32 /m /v:m /nologo
```

Output: `Debug\microsip.exe` (x86, 15.8 MB, file version 3.22.16).

**Only `Debug|Win32` is viable.** The prebuilt pjsip library exists solely as
`libpjproject-i386-Win32-vc14-Debug-Static.lib`:

* `Release|Win32` would select `…-Release-Static.lib`, which is not available;
* `x64` and `ARM64` have no prebuilt pjsip library at all.

Building pjsip from source for x64 is possible in principle, but the tree also
needs the author's private `build/vs/*.props` and their patched pjproject
sources, so it is not a practical route.

### Prerequisites

* Visual Studio 2022 (toolset `v143`) **or** Visual Studio 2026 (toolset `v145`)
* **MFC** — `Microsoft.VisualStudio.Component.VC.ATLMFC`. The C++ workload
  installs ATL only; without MFC the build stops with `error MSB8041`.
* Windows SDK 10.0.26100.0 or newer

---

## 7. Verified result

`Debug\microsip.exe` starts, shows its main window (`MainWindowTitle:
'MicroSIP'`), keeps 11–12 threads alive (pjsip worker/timer threads) and
creates `call_log.db` with the expected schema:

```
call_log(id, callId, number, name, type, time, duration, info)
idx_call_log_callId_unique
```

Only `microsip.exe` itself is loaded from outside `C:\Windows`, i.e. pjsip,
opus, sqlite3 and MFC are all statically linked in.

---

## 8. Licensing note

The prebuilt pjsip static library and `opus.lib` come from a third-party
repository that mirrors the author's build tree. `bcg729` is GPLv3 (or a
commercial licence from Belledonne Communications) — distributing a binary
built from it carries the corresponding obligations. MicroSIP itself is GPLv2.
