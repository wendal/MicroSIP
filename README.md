# MicroSIP — self-contained build

MicroSIP 3.22.16, the open-source SIP softphone, packaged so that **one
clone is enough to build the executable**.

The official source release (`MicroSIP-3.22.16-src.7z`) contains only the
application sources. `microsip.vcxproj` expects to sit next to a full
dependency tree that upstream does not ship:

> MicroSIP relies on third-party libraries that are **not included in this
> repository**.

This repository closes that gap. The pjproject headers, every source archive
and the one prebuilt library live in `third_party\`, and `build\build.ps1`
compiles the whole thing — no second checkout, no download while building.

## Quick start

```powershell
git clone git@gitee.com:wendal/microsip.git
cd microsip
.\build\build.ps1
```

The first run checks the toolchain, unpacks the vendored sources, builds
SQLiteCpp / bcg729 / opus / OpenSSL, builds the pjproject static library for
x64 and then the application. It takes about 13 minutes on a current
developer machine; every later run reuses what is already there.

Output:

| Configuration | Binary |
|---|---|
| `x64\|Debug` | `x64\Debug\microsip.exe` |
| `x64\|Release` | `x64\Release\microsip.exe` |
| `Debug\|Win32` | `Debug\microsip.exe` |

`Release\|Win32` is intentionally skipped — only the Debug flavour of the
32-bit pjproject library is vendored, and the pipeline says so instead of
failing.

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
build keeps seeing exactly the feature set of the library it links against.

## Layout

```
build\          the build pipeline - see build\README.md
  build.ps1     single entry point
  steps\        00-check-toolchain … 04-app
  stub\         chkstk_ms.c - the placeholder archive the project file demands
  vs\           the upstream pjproject Visual Studio property sheets
third_party\    the dependency tree - see third_party\README.md
  src\          source archives (git-lfs)
  lib\          the prebuilt 32-bit pjproject library + the generated x64 ones
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
.\tools\verify-pjproject-provenance.ps1
```

## Provenance

The dependency tree is not a private fork. The pjproject headers are
**byte-identical to upstream pjproject 2.14.1** (305 / 305 files), the
prebuilt 32-bit library exports **only** upstream symbols (2266, zero
author-only APIs), and the `build\vs\` property sheets are upstream's own.
`BUILD.md` §9 documents the verification and `tools\verify-pjproject-provenance.ps1`
re-runs it.

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
