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

## 1. Layout of the repository

Everything the build needs is **inside** the repository:

```
MicroSIP-3.22.16-src\
├─ build\               the build pipeline (details in build\README.md)
│  ├─ build.ps1         single entry point
│  ├─ steps\            00-check-toolchain … 04-app
│  ├─ stub\             chkstk_ms.c - the placeholder archive (see §5)
│  ├─ vs\               the upstream pjproject Visual Studio property sheets
│  └─ work\             unpacked sources and intermediate objects (git-ignored)
├─ third_party\         the dependency tree (details in third_party\README.md)
│  ├─ src\              source archives, tracked with git-lfs
│  ├─ lib\              the prebuilt 32-bit pjproject library + the generated x64 ones
│  ├─ pj\, pjsip\ …     the pjproject headers, flattened
│  └─ MANIFEST.txt      SHA-256 of every vendored archive
├─ tools\               verification scripts (not part of the build)
└─ microsip.vcxproj     the application
```

A clone plus one command is enough — nothing is downloaded while building:

```powershell
git clone git@gitee.com:wendal/microsip.git
cd microsip
.\build\build.ps1
```

(The same repository is also pushed to `git@github.com:wendal/MicroSIP.git`.)

---

## 2. Where every dependency came from

| Dependency | Source |
|---|---|
| `build/vs/pjproject-vs14-common-config.props` (+ `…-api-def.props`) | **Verbatim from upstream pjproject 2.14.1** — pjproject's own VS property sheet, not a private file. See §3 and §9. |
| `third_party\pj\`, `third_party\pjsip\`, … (pjproject headers) | **Stock upstream pjproject 2.14.1** (verified in §9), taken from the official dependency repository `github.com/guilhermejansen/MicroSIP-Com-Deps` (branch `master`) which publishes exactly this flattened `third_party/` tree. The author's own workspace tree `github.com/pythonist77/microsip` is a pjproject checkout of the 2.8→2.9 development window (2019) with `MicroSIP-3.19.17-src/` inside it — upstream trunk, not a private fork. |
| `third_party\lib\libpjproject-i386-Win32-vc14-Debug-Static.lib` | The same repository — the prebuilt 32-bit pjproject library. The Win32 build of the application links it (rebuilding pjproject for Win32 is out of scope). |
| `third_party\src\pjproject-2.14.1.zip` | Upstream pjproject release archive — compiled for x64 by the pipeline. |
| `third_party\src\openssl-3.0.15.zip` | Upstream OpenSSL release archive (Apache-2.0). |
| `third_party\src\opus-1.3.1.zip` | Upstream Opus release archive (BSD-3-Clause) — `github.com/xiph/opus`. |
| `third_party\src\bcg729.zip` | `github.com/Lekensteyn/bcg729` (ITU G.729 Annex A/B codec). |
| `third_party\src\SQLiteCpp-3.4.0.zip` | `github.com/SRombauts/SQLiteCpp` tag **3.4.0** (bundles sqlite3). |
| `chkstk_ms.lib` | **Generated stub** — the name is an ARM64-only library; it does not exist for x86/x64 in any Windows SDK. See §5. |

The archives are tracked with **git-lfs** (see `.gitattributes`), so a clone
brings them along; `third_party\MANIFEST.txt` records the SHA-256 of each one.

Downloads were made through the `gh-proxy.com` mirror (`github.com` is not
directly reachable from this network; `codeload.github.com` is).

```powershell
curl.exe -sSL -o deps.zip "https://gh-proxy.com/https://github.com/guilhermejansen/MicroSIP-Com-Deps/archive/refs/heads/master.zip"
curl.exe -sSL -o sqlitecpp.zip "https://codeload.github.com/SRombauts/SQLiteCpp/zip/refs/tags/3.4.0"
curl.exe -sSL -o bcg729.zip   "https://codeload.github.com/Lekensteyn/bcg729/zip/refs/heads/master"
```

`build\import-deps.ps1` performs that vendoring step once and records the
hashes; it is not needed for an ordinary build.

---

## 3. `build/vs/pjproject-vs14-common-config.props`

This file is **not author-private**. It is pjproject's own Visual Studio
property sheet: the author's workspace tree carries a `build/vs/` folder whose
**34 files are byte-identical (SHA-256) to upstream pjproject 2.8's
`build/vs/`**, this one included. Every pjproject release from 2.8 on ships
it, so it can simply be copied out of the pjproject source tree.

The upstream file hard-codes `<BuildToolset>v140</BuildToolset>`, which no
longer ships with current Visual Studio installations, so the reconstruction
below (same contract, modern toolset) is used instead. It supplies three
things the project file consumes:

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
third_party\SQLiteCpp\Win32\Debug\{SQLiteCpp,sqlite3}.lib
third_party\bcg729\Win32\Debug\bcg729.lib
third_party\opus\Win32\Debug\opus.lib
third_party\lib\libpjproject-i386-Win32-vc14-Debug-Static.lib
```

For x64 the same layout is used with the platform segment, which the project
file already parameterises as `$(Platform)` / `$(Configuration)`:

```
third_party\SQLiteCpp\x64\Debug\{SQLiteCpp,sqlite3}.lib
third_party\SQLiteCpp\x64\Release\{SQLiteCpp,sqlite3}.lib
third_party\bcg729\x64\{Debug,Release}\bcg729.lib
third_party\opus\x64\{Debug,Release}\opus.lib
third_party\openssl\x64\{Debug,Release}\lib\{libcrypto,libssl}.lib
third_party\lib\libpjproject-x86_64-x64-vc14-{Debug,Release}-Static.lib
```

See §10 for how those are produced.

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

**Out of the box only `Debug|Win32` links**, because the prebuilt pjsip library
exists solely as `libpjproject-i386-Win32-vc14-Debug-Static.lib`:

* `Release|Win32` would select `…-Release-Static.lib`, which is not available;
* `x64` and `ARM64` have no prebuilt pjsip library at all.

**All of that is fixable by building pjsip yourself** — the dependency is
**stock upstream pjproject 2.14.1** (see §9) and the VS property sheet comes
from pjproject itself, so no author-private patch is required. What has to
match is the compile configuration: `PJ_WIN64=1;PJ_M_X86_64=1` (or
`PJ_WIN32=1;PJ_M_I386=1`), `/MTd` for Debug / `/MT` for Release, and
`PJMEDIA_HAS_VIDEO=1`, otherwise the header/lib ABI diverges. §10 documents
the full x64 route.

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
repository that mirrors the author's build tree. `bcg729` is **GPL-2.0** (its
upstream README says "The source code is licensed under GPLv2", and the
`COPYING` file in the archive is the GPL version 2 text) — distributing a
binary built from it carries the corresponding obligations. MicroSIP itself is
GPLv2. Every vendored licence is collected verbatim in
`third_party\LICENSES\`.

PJSIP itself is **not** closed source: upstream pjproject is GPLv2 (or, at
Teluu's option, a commercial licence), and MicroSIP is GPLv2, so the GPLv2
terms carry through to the statically linked binary. See §9.

---

## 9. Provenance of the pjproject dependency (verified)

Everything below was checked against upstream sources; nothing is inferred.

| Check | Result |
|---|---|
| pjproject headers in `third_party/` vs upstream pjproject **2.14.1** | **305 / 305 byte-identical**, 0 differences (the only other pjproject file there, `pj/config_site.h`, has no upstream counterpart by design) |
| `third_party/pj/config_site.h` vs upstream `config_site_sample.h` | identical **except one added line**: `#define PJMEDIA_HAS_VIDEO 1` |
| Objects inside `libpjproject-i386-Win32-vc14-Debug-Static.lib` | 439 distinct modules — 410 map to upstream pjproject sources; the other **29 are libyuv** (upstream's own `third_party/yuv`, whose sources upstream fetches at build time and does not ship in the release zip) |
| Exported C symbols of that lib | 2266 symbols — **every one** exists in upstream 2.14.1 (20 are internal symbols that live only in upstream `.c` files); **0 author-only APIs** |
| `build/vs/` in the author's tree vs upstream pjproject 2.8 | **34 / 34 files byte-identical** (SHA-256) |
| Author's 2019 tree vs upstream 2.8 / 2.9 | 1239 `.c/.h` files: 1081 identical to 2.8, 115 identical to 2.9 only, 43 matching neither — of those 43, 33 are the MicroSIP app itself, 4 are upstream's sample CLI app (`pjsip-apps`), and **6 are pjproject-core files that are upstream 2.9 plus a 2–4 line local delta** (`config_site.h`, `config.h` version string, `ip_helper_win32.c`, `ssl_sock_imp_common.h`, `ssl_sock_ossl.c`, `sip_resolve.c`) |

**Conclusion:** the prebuilt pjproject library is *stock upstream pjproject
2.14.1* plus upstream's own libyuv, compiled with the author's Visual Studio
settings (`vc14`, `i386`, `Debug`, `Static`, `/MTd`) and the `config_site.h`
above. There is no author-patched pjproject source in the dependency tree and
no author-only API.

The author's workspace tree (`github.com/pythonist77/microsip`, GPL-2.0) is a
pjproject checkout of the **2.8 → 2.9 development window** (2019) with
`MicroSIP-3.19.17-src/` inside it — i.e. upstream trunk with a handful of
one-line local deltas, **not a private fork**.

Two consequences worth knowing:

* The MicroSIP source package is designed to sit **inside a pjproject
  checkout** — `microsip.vcxproj` imports `..\build\vs\…props` and includes
  `..\pjlib\include`, `..\pjsip\include`, `..\pjmedia\include`,
  `..\pjnath\include`, `..\pjlib-util\include`, so `..` must be the pjproject
  root. The pjproject static library is bound by name, not by project
  reference: `mainDlg.h` carries
  `#pragma comment(lib, "libpjproject-i386-Win32-vc14-Debug-Static.lib")`
  (and the `…-Release-Static.lib` variant under `NDEBUG`) — which is why the
  release ships no `.sln` and why the library name encodes the toolset,
  architecture, configuration and linkage. `mainDlg.h` now selects the
  library per architecture (`_M_X64` → `libpjproject-x86_64-x64-vc14-*.lib`),
  which is what makes the x64 build in §10 possible.
* Replacing the prebuilt library with your own build of upstream 2.14.1 is
  viable. Match the compile configuration (`PJ_WIN32=1;PJ_M_I386=1`, `/MTd`,
  `PJMEDIA_HAS_VIDEO=1`) or the header/library ABI diverges.

### Reproducing the checks

`tools/verify-pjproject-provenance.ps1` re-runs everything in this section
from scratch (headers, library modules, exported symbols, author tree):

```powershell
.\tools\verify-pjproject-provenance.ps1 `
    -UpstreamRoot  C:\src\pjproject-2.14.1 `
    -UpstreamRoot2 C:\src\pjproject-2.9 `
    -HeaderTree    .\third_party `
    -AuthorTree    C:\src\microsip-master `
    -Lib           .\third_party\lib\libpjproject-i386-Win32-vc14-Debug-Static.lib
```

Those four trees are **not** part of this repository — they are the upstream
checkouts the comparison is made against. Fetch them separately if you want to
re-run the provenance proof; the ordinary build does not need them.

Two pitfalls it deliberately avoids:

* **Never use `Get-ChildItem -Recurse -Include` on a literal path.** Without a
  trailing `\*` the `-Include` filter behaves inconsistently and silently
  under-reports files — that produced wrong counts during the original
  investigation. Filter on `Extension` instead.
* **Never use `git diff --no-index` for whole-tree comparisons.** It walks
  third-party codec sources and times out; hash-based comparison finishes in
  seconds and is stronger (byte equality vs line proximity).

---

## 10. Building x64 (and the other configurations)

Because the pjproject dependency is stock upstream (§9), the missing
configurations can be produced locally. This has been done for x64; `Debug`,
`Release` and `ARM64` follow the same recipe.

### 10.1 What was built

| Artefact | How |
|---|---|
| `third_party\lib\libpjproject-x86_64-x64-vc14-Debug-Static.lib` | upstream pjproject 2.14.1, `Debug-Static\|x64` |
| `third_party\lib\libpjproject-x86_64-x64-vc14-Release-Static.lib` | upstream pjproject 2.14.1, `Release-Static\|x64` |
| `third_party\SQLiteCpp\x64\Debug\{sqlite3,SQLiteCpp}.lib` | SQLiteCpp 3.4.0, `/MTd` |
| `third_party\SQLiteCpp\x64\Release\{sqlite3,SQLiteCpp}.lib` | SQLiteCpp 3.4.0, `/MT` |
| `third_party\bcg729\x64\{Debug,Release}\bcg729.lib` | bcg729, `/MTd` / `/MT` |
| `third_party\opus\x64\{Debug,Release}\opus.lib` | opus 1.3.1, `win32\VS2015\opus.vcxproj` |

**Feature parity check:** before Opus and TLS were switched on (§11), the
freshly built x64 library exported **exactly the same 2266 `pj*` symbols** as
the official 32-bit prebuilt library — zero missing, zero extra:

```powershell
.\tools\compare-lib-symbols.ps1 `
    -LibA .\third_party\lib\libpjproject-i386-Win32-vc14-Debug-Static.lib `
    -LibB .\third_party\lib\libpjproject-x86_64-x64-vc14-Debug-Static.lib
```

Both libraries carry SRTP, the H.264 and VPX packetizers, and — like the
official one — **no Opus codec and no OpenSSL/TLS backend**, because
`PJMEDIA_HAS_OPUS_CODEC` and `PJ_HAS_SSL_SOCK` both default to 0. Enabling
Opus and TLS is a deliberate extra (§11), not a parity gap.

### 10.2 Recipe

The whole thing is one command (see §12):

```powershell
# everything: toolchain check, dependencies, third-party libraries,
# the x64 pjproject library and the application
.\build\build.ps1

# or just the x64 half
.\build\build.ps1 -Platform x64 -Configuration Debug
.\build\build.ps1 -Platform x64 -Configuration Release
```

The individual stages can also be run on their own — each one is idempotent
and skips what it has already produced:

```powershell
.\build\build.ps1 -Step prepare
.\build\build.ps1 -Step thirdparty
.\build\build.ps1 -Step pjproject
.\build\build.ps1 -Step app
```

### 10.3 Points that will bite you

* **The toolset override.** Upstream's `build/vs/pjproject-vs14-common-config.props`
  hardcodes `v140`, which no longer ships. A global `/p:BuildToolset=v145`
  overrides the props file (global properties win). For projects that hardcode
  `<PlatformToolset>v140</PlatformToolset>` in their own `PropertyGroup`
  (opus does), use `/p:PlatformToolset=v145` instead — `/p:BuildToolset`
  cannot reach it.
* **Library naming.** pjproject's own props derive the name from both the
  target CPU and the platform: `libpjproject-x86_64-x64-vc14-…lib` for x64
  (not `…-Win32-…` like the 32-bit one). `mainDlg.h` must select it
  accordingly, otherwise the linker looks for the 32-bit name.
* **32-bit archives must not sit in `lib\`.** `lib\` is on the library path of
  *every* platform. `opus.lib` and `bcg729.lib` were moved to
  `third_party\opus\Win32\` and `third_party\bcg729\Win32\`, which the
  project file already lists as `..\third_party\opus\$(Platform)\` and
  `..\third_party\bcg729\$(Platform)\`.
* **CRT consistency.** Debug uses `/MTd` everywhere, Release uses `/MT`.
  Mixing them produces the misleading `LNK4098` + `LNK2019` pair described in
  §5. This bites much harder once Opus or OpenSSL is switched on, because
  those archives then actually get pulled into the link — see §11.3.

### 10.4 Verified result

| Configuration | Output | Size | Runs |
|---|---|---|---|
| `Debug\|x64` | `x64\Debug\microsip.exe` | 20.8 MB | window `MicroSIP`, 12 threads, `call_log.db` created |
| `Release\|x64` | `x64\Release\microsip.exe` | 6.8 MB | window `MicroSIP`, 24 threads, `call_log.db` created |
| `Debug\|Win32` (regression) | `Debug\microsip.exe` | 16.5 MB | window, 12 threads, `call_log.db` created |

`tools\verify-app.ps1` performs that smoke test (architecture check, window
title, thread count, database creation).

---

## 11. Extra features: Opus codec and TLS

Two optional features were added on top of the stock upstream pjproject. Both
are switched through `pj/config_site.h` and both are opt-in.

| Feature | Macro | Implemented in |
|---|---|---|
| Opus encoder/decoder | `PJMEDIA_HAS_OPUS_CODEC` | `pjmedia/src/pjmedia-codec/opus.c` |
| SIP over TLS | `PJ_HAS_SSL_SOCK` | `pjlib/src/pj/ssl_sock_ossl.c` (OpenSSL backend) |

```powershell
# the macros are written into both copies of config_site.h by the pipeline
.\build\build.ps1 -Step prepare
```

(`tools\enable-pjproject-features.ps1` used to do this; it is retired — the
macro set now lives in `build\steps\01-prepare.ps1`, which writes the two
identical copies of `config_site.h`.)

### 11.1 One `config_site.h`, two copies

`pj/config.h` includes `<pj/config_site.h>` unconditionally, so the macros
decide what is compiled *into* the library **and** what the application
believes the library contains. The pipeline therefore writes the identical
file into

* `pjproject-2.14.1\pjlib\include\pj\config_site.h` (library build)
* `third_party\pj\config_site.h` (application build)

The macros are guarded by `#if defined(_M_X64)`:

```c
#if defined(_M_X64)
#  define PJMEDIA_HAS_OPUS_CODEC 1
#  define PJ_HAS_SSL_SOCK 1
#else
#  define PJMEDIA_HAS_OPUS_CODEC 0
#  define PJ_HAS_SSL_SOCK 0
#endif
```

The locally built x64 library has both features; the 32-bit library that ships
with MicroSIP was compiled without them. The Win32 build of the application
links that 32-bit library, so it has to see the same macro set — otherwise the
headers promise features the binary does not have.

### 11.2 Third-party archives are per (platform, configuration)

`..\third_party\opus\$(Platform)\` and `..\third_party\bcg729\$(Platform)\`
were replaced by `..\third_party\opus\$(Platform)\$(Configuration)\` and
`..\third_party\bcg729\$(Platform)\$(Configuration)\` — the pattern the project
file already used for SQLiteCpp. `build\steps\02-thirdparty.ps1` builds all four
variants (x64/Win32 × Debug/Release) with the matching CRT.

### 11.3 The two traps that cost the most time

#### The shared `third_party\lib` folder shadows the per-platform folders

The library search path is

```
..\lib\ ; ..\third_party\lib\ ; ..\third_party\openssl\$(Platform)\lib\ ; …
                ..\third_party\opus\$(Platform)\$(Configuration)\ ; …
```

`..\third_party\lib\` comes **first**, and the MicroSIP source release ships
x86 `opus.lib` and `bcg729.lib` there. The linker therefore picked the
**32-bit** `opus.lib` for the x64 build, and the x64 references coming out of
`libpjproject-…lib(opus.obj)` could not be satisfied:

```
LNK2019 unresolved external symbol opus_strerror / opus_encode / opus_encoder_init
```

which looks exactly like a link-order problem but is really a *wrong bitness*
problem — moving `opus.lib` around on the command line changes nothing while
that x86 copy is still first in the search path. The pipeline therefore keeps
the shared `third_party\lib` free of architecture-specific archives: every
`opus.lib` / `bcg729.lib` lives only in its `$(Platform)\$(Configuration)`
folder.

#### The CRT has to match — and it only shows up once the feature is on

The x86 `opus.lib` shipped upstream is a **release** build (`/DEFAULTLIB:LIBCMT`),
while the application's `Debug` configuration uses `/MTd`. Upstream never
noticed, because the shipped 32-bit pjproject was compiled *without* Opus, so
`opus.lib` was never pulled into the link and no conflict could arise.

The moment `PJMEDIA_HAS_OPUS_CODEC` is enabled the archive becomes reachable
and the mismatch surfaces as

```
LINK : warning LNK4098: default library 'libcmt.lib' conflicts with other libraries' use
```

LNK4098 is a warning, but it means **two CRT heaps in one process**: the
archive allocates with one CRT and the application frees with the other.
Building every third-party archive per configuration removes the problem
(verified: the final executables import no CRT DLL at all).

### 11.4 OpenSSL

| | |
|---|---|
| Version | 3.0.15 (LTS), built from the GitHub tag archive |
| Target | `VC-WIN64A`, `no-shared no-module no-tests no-legacy no-asm` |
| CRT | `/MTd` for Debug, `/MT` for Release — one build per configuration |
| Install | `third_party\openssl\<Platform>\<Configuration>\lib\{libcrypto,libssl}.lib` |
| Headers | `third_party\openssl\Win32\include` (path the project file already had) |

```powershell
# one OpenSSL build per configuration, produced by the pipeline
.\build\build.ps1 -Step thirdparty -Platform x64 -Configuration Debug
.\build\build.ps1 -Step thirdparty -Platform x64 -Configuration Release
```

Three details are worth recording:

* **The provider archives are separate.** With `no-module`, OpenSSL 3.x still
  builds the providers as `providers\libdefault.lib` and
  `providers\libcommon.lib`, and `libcrypto` references their symbols. They
  are merged into `libcrypto.lib` with `lib.exe`, so the single
  `#pragma comment(lib, "libcrypto")` in `ssl_sock_ossl.c` keeps working no
  matter where the archive sits on the link line.
* **OpenSSL's objects carry no CRT default library.** The generated makefile
  compiles them with `/Zl`, which omits the `/DEFAULTLIB` entry. The CRT is
  therefore supplied by the application itself — no LNK4098, and no second CRT
  in the image.
* **The include path is needed by more than pjlib.** `pjsip_core` needs
  `openssl/sha.h` (HTTP digest authentication) and `pjmedia` needs
  `openssl/rand.h` (DTLS-SRTP), so `build\steps\03-pjproject.ps1` imports the
  local props file into *every* pjproject project.

### 11.5 Verified result

| Check | Tool | Result |
|---|---|---|
| OpenSSL is static and usable | `tools\verify-openssl.ps1` | `SSL_CTX_new` → **60 cipher suites**, default provider loadable |
| pjsua can create a TLS transport | `tools\verify-tls.ps1` | `SIP TLS listener is ready for incoming connections at …:5061` |
| TLS/Opus code is in the executable | PDB symbol scan | `pj_ssl_sock_start_connect`, `SSL_CTX_new`, `SSL_new`, `ossl_provider_init`, `pjmedia_codec_opus_init`, `opus_encode` |
| The application really listens for TLS | socket inspection | `TCP 0.0.0.0:5061 LISTEN` — the TLS transport MicroSIP creates at startup |
| No mixed CRT | import table | no `msvcrt*.dll` / `ucrtbase.dll` import |

| Configuration | Output | Size | Runs |
|---|---|---|---|
| `Debug\|x64` | `x64\Debug\microsip.exe` | 26.1 MB | window `MicroSIP`, 24 threads, `call_log.db` created |
| `Release\|x64` | `x64\Release\microsip.exe` | 10.1 MB | window `MicroSIP`, 12 threads, `call_log.db` created |
| `Debug\|Win32` (regression) | `Debug\microsip.exe` | 16.5 MB | builds and runs, Opus/TLS off as intended |

---

## 12. One repository, one command

The whole build now lives inside the repository. `git clone` plus
`build\build.ps1` is the complete procedure — no second checkout, no download
while building.

```powershell
git clone <this repository>
cd MicroSIP-3.22.16-src
.\build\build.ps1
```

### 12.1 What is tracked

| Path | Tracked | Notes |
|---|---|---|
| `third_party\pj\`, `third_party\pjsip\`, … | yes (text) | pjproject 2.14.1 headers, flattened, byte-identical to upstream (§9) |
| `third_party\lib\libpjproject-i386-…-Static.lib` | yes (**git-lfs**) | the prebuilt 32-bit library the Win32 build links |
| `third_party\src\*.zip` | yes (**git-lfs**) | the source archives everything else is built from |
| `build\` | yes (text) | the pipeline, the `chkstk_ms` stub, the upstream VS property sheets |
| `third_party\opus\`, `bcg729\`, `SQLiteCpp\`, `openssl\` | no | generated by the pipeline |
| `build\work\` | no | unpacked sources and intermediate objects |

`third_party\MANIFEST.txt` records the SHA-256 of every vendored archive. Every
path in it is relative to `third_party\`, so the manifest can be checked
directly after a clone:

```powershell
.\tools\verify-manifest.ps1
```

```
   [ok]   src/bcg729.zip  (221,819 bytes)
   [ok]   src/openssl-3.0.15.zip  (18,271,384 bytes)
   [ok]   src/opus-1.3.1.zip  (4,806,880 bytes)
   [ok]   src/pjproject-2.14.1.zip  (12,433,561 bytes)
   [ok]   src/SQLiteCpp-3.4.0.zip  (2,911,290 bytes)
   [ok]   lib/libpjproject-i386-Win32-vc14-Debug-Static.lib  (15,959,216 bytes)

RESULT: all 6 vendored archives match the manifest.
```

The archives live in the local git-lfs object store
(`.git\lfs\objects`, 52 MB for the six of them). This repository has **no
remote configured** — when one is added, `git push` uploads the lfs objects
through the pre-push hook, and a clone on the other side gets the real files
instead of the pointer stubs.

### 12.2 The pipeline

| Step | Script | What it does |
|---|---|---|
| 0 | `build\steps\00-check-toolchain.ps1` | reports every missing tool and the command that installs it |
| 1 | `build\steps\01-prepare.ps1` | unpacks `third_party\src\*.zip`, stages the third-party headers, generates `pj\config_site.h` |
| 2 | `build\steps\02-thirdparty.ps1` | builds SQLiteCpp, bcg729, opus, the `chkstk_ms` placeholder and (for x64) OpenSSL — per platform **and** configuration |
| 3 | `build\steps\03-pjproject.ps1` | patches and builds the pjproject static library for x64 |
| 4 | `build\steps\04-app.ps1` | builds `microsip.vcxproj` |

### 12.3 What had to change in the project file

The released `microsip.vcxproj` addresses its dependencies through `..`,
because in the author's layout the dependency tree is a *sibling* of the
application folder:

```
..\third_party\...   ->  third_party\...
..\lib\              ->  third_party\lib\$(Platform)\  +  third_party\lib\
```

The dead `..\pjlib\include`, `..\pjsip\include`, … entries were dropped: the
headers are flattened into `third_party\`, which is on the include path.

The Visual Studio property sheet that the project imports
(`..\build\vs\pjproject-vs14-common-config.props`) is vendored in `build\vs\`
instead — **byte-identical to upstream pjproject 2.14.1**, so the provenance
argument of §9 is unaffected. It needs its sibling
`pjproject-vs14-api-def.props`, which is vendored next to it.

### 12.4 The toolset

The upstream property sheet hardcodes `v140`, which no longer ships. The
pipeline detects the installed toolset and passes `/p:BuildToolset=…`. With
Visual Studio 2026 that is `v145` — note that the folder names and the
toolset names are different series: the toolset lives in
`MSBuild\Microsoft\VC\v180\Platforms\Win32\PlatformToolsets\v145`.

### 12.5 Things the single-repository build had to get right

* **The OpenSSL headers are staged after `Configure`, not before.** OpenSSL
  generates `opensslconf.h`, `configuration.h` and friends while configuring;
  the pristine archive only contains the templates. Staging the archive gives
  137 header files, the configured tree 162 — and `pjlib` needs the
  generated ones.
* **`chkstk_ms.lib` is generated, not vendored.** It is an ARM64-only archive
  that does not exist for x86/x64, but `microsip.vcxproj` lists it in every
  configuration. `build\stub\chkstk_ms.c` is a one-function placeholder,
  compiled with `/Zl` so that it does not drag a CRT into the link.
* **The shared `third_party\lib` stays free of architecture specific
  archives** — it is searched before the per-platform folders (§11.3).
* **Every archive is built per configuration** so that its CRT matches
  (§11.3).
* **OpenSSL is built for x64 only.** The Win32 application links the vendored
  32-bit pjproject library, which was compiled *without* a TLS backend — it
  exports neither `pj_ssl_sock_start_connect` nor any `SSL_*` / `EVP_*` symbol
  (only the pjsip TLS API layer `pj_ssl_sock_param_copy` and friends). Nothing
  in the Win32 link therefore references OpenSSL, and building it would cost
  ~20 minutes for archives nobody links. `build\steps\02-thirdparty.ps1` skips
  it and says so; `-BuildSslWin32` forces it.
* **OpenSSL's 32-bit target is `VC-WIN32`, not `VC-WIN32A`.** `Configure`
  rejects the latter and prints its whole target table, which is easy to
  mistake for a broken compiler:
  ```
  Configuring OpenSSL version 3.0.15 for target VC-WIN32A
  Usage: Configure [no-<cipher> ...] ...
  pick os/compiler from: BC-32 BS2000-OSD … VC-WIN32 VC-WIN64A …
  ```
* **`Release|Win32` is skipped, not attempted.** Only the Debug flavour of the
  32-bit pjproject library is vendored, so the Release link would look for
  `libpjproject-i386-Win32-vc14-Release-Static.lib` and fail. Step 4 detects
  the missing archive and skips that configuration with an explanation.


