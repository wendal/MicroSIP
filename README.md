# MicroSIP — self-contained build

MicroSIP 3.23.5, the open-source SIP softphone, packaged so that **one
clone is enough to build the executable**.

The official source release (`MicroSIP-3.23.5-src.7z`) contains only the
application sources. `microsip.vcxproj` expects to sit next to a full
dependency tree that upstream does not ship:

> MicroSIP relies on third-party libraries that are **not included in this
> repository**.

This repository closes that gap. The pjproject headers and every source
archive live in `third_party\`, and `build\build.ps1` compiles the whole thing —
no second checkout, no download while building.

## Quick start

```powershell
git clone git@gitee.com:wendal/microsip.git
cd microsip
.\build\build.ps1
```

The first run checks the toolchain, unpacks the vendored sources, builds
SQLiteCpp / bcg729 / opus / OpenSSL, builds the pjproject static library for
x64 and Win32 and then the application. Measured from a fresh clone: **12 min
53 s** on a current developer machine — every later run reuses what is already
there.

Output:

| Configuration | Binary |
|---|---|
| `x64\|Debug` | `x64\Debug\microsip.exe` |
| `x64\|Release` | `x64\Release\microsip.exe` |
| `Win32\|Debug` | `Debug\microsip.exe` |
| `Win32\|Release` | `Release\microsip.exe` |

All four configurations are built from the same sources; nothing is skipped.

### Requirements

`build\build.ps1` starts with a toolchain check that prints every missing
tool together with the command that installs it:

| Tool | Needed for |
|---|---|
| Visual Studio 2022 / 2026, "Desktop development with C++", **including MFC** | everything |
| Windows 10 SDK | everything |
| Strawberry Perl | building OpenSSL (the TLS backend) |
| git-lfs | fetching `third_party\src` |
| NASM | *optional* — OpenSSL is built `no-asm` without it |

```powershell
winget install --id Microsoft.VisualStudio.2022.Community
winget install --id StrawberryPerl.StrawberryPerl
winget install --id GitHub.GitLFS
```

## What you get beyond a plain build

The x64 pjproject library is compiled from the vendored upstream source with
two features switched on that the official 32-bit release does not have:

* **Opus codec** (`PJMEDIA_HAS_OPUS_CODEC`)
* **SIP over TLS** (`PJ_HAS_SSL_SOCK`, OpenSSL 3.0.15 backend)

Both are guarded by `#if defined(_M_X64)` in `pj\config_site.h`, so the Win32
build keeps seeing exactly the feature set of the library it links against —
OpenSSL is only built for x64, and the Win32 pjproject is compiled without a
TLS backend.

### pjproject version

The vendored pjproject is **2.17** — the same release upstream MicroSIP 3.23.x
ships, and the one the 3.23.5 sources are written against. Every platform is
compiled from that one archive by `build\steps\03-pjproject.ps1`, so the
application and the library it links against can never drift apart.

Nothing is vendored prebuilt any more: the 32-bit library that used to sit in
`third_party\lib\` was a 2.14.1 build and would have been ABI-incompatible with
the 2.17 headers. Building Win32 from source removes that trap and makes
`Release|Win32` possible.

## Layout

```
build\          the build pipeline - see build\README.md
  build.ps1     single entry point
  steps\        00-check-toolchain … 04-app
  stub\         chkstk_ms.c - the placeholder archive the project file demands
  vs\           the upstream pjproject Visual Studio property sheets
third_party\    the dependency tree - see third_party\README.md
  src\          source archives (git-lfs)
  lib\          build output: the pjproject and helper archives (git-ignored)
  LICENSES\     the licence of every vendored dependency
tools\          verification scripts (not part of the build)
BUILD.md        the full story: provenance, the traps, the measurements
```

## Verifying

```powershell
.\tools\verify-manifest.ps1     # SHA-256 of every vendored archive
.\tools\verify-app.ps1 -Exe .\x64\Release\microsip.exe
.\tools\verify-openssl.ps1 -Configuration Debug
.\tools\verify-tls.ps1 -Configuration Debug
.\tools\verify-pjproject-provenance.ps1 `
    -UpstreamRoot .\build\work\pjproject-2.17 -HeaderTree .\third_party
```

## Provenance

The dependency tree is not a private fork. The pjproject headers are
**byte-identical to upstream pjproject 2.17** — the flattened tree is a pure
function of the archive's five include directories, and
`tools\verify-pjproject-provenance.ps1` re-derives it and compares file by
file. The `build\vs\` property sheets are upstream's own. `BUILD.md` §9
documents the verification.

## Licensing

* The application is **GPL-2.0** — see `LICENSE`.
* pjproject is GPL-2.0 (or a commercial licence from Teluu) and is statically
  linked into the executable, so the GPL-2.0 terms carry through to the
  binary.
* OpenSSL is Apache-2.0, Opus is BSD-3-Clause, bcg729 is GPL-2.0,
  SQLiteCpp is MIT and SQLite is in the public domain.
* `third_party\LICENSES\` holds each of those texts verbatim.

## Documentation

* `BUILD.md` — the complete build story, the provenance proof, and every
  trap that had to be solved (CRT mismatches, the wrong-bitness `opus.lib`,
  `chkstk_ms.lib`, the OpenSSL target names).
* `build\README.md` — the pipeline, step by step.
* `third_party\README.md` — what is vendored and what is generated.
