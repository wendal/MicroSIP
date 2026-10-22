# Building MicroSIP from this repository

This directory contains the complete build pipeline. Everything it needs is
inside the repository — no other checkout, no downloads.

```powershell
git clone <this repository>
cd MicroSIP-3.22.16-src
.\build\build.ps1
```

The result lands in `x64\Debug\microsip.exe` and `x64\Release\microsip.exe`
(the Win32 build lands in `Debug\` and `Release\`).

## Prerequisites

`build\build.ps1` starts with a toolchain check and prints every missing
tool together with the command that installs it:

| Tool | Needed for | Install |
|---|---|---|
| Visual Studio 2022 / 2026 with "Desktop development with C++" | everything | `winget install --id Microsoft.VisualStudio.2022.Community` |
| Windows 10 SDK | everything | ships with Visual Studio |
| Strawberry Perl | OpenSSL (TLS) | `winget install --id StrawberryPerl.StrawberryPerl` |
| git-lfs | pulling `third_party\src` | `winget install --id GitHub.GitLFS` |
| NASM | *optional* — OpenSSL is built `no-asm` without it | `winget install --id NASM.NASM` |

## The steps

| Step | Script | What it does |
|---|---|---|
| 0 | `steps\00-check-toolchain.ps1` | reports missing tools and how to install them |
| 1 | `steps\01-prepare.ps1` | unpacks `third_party\src\*.zip` into `build\work\`, stages the third-party headers into `third_party\`, generates `pj\config_site.h` |
| 2 | `steps\02-thirdparty.ps1` | builds SQLiteCpp, bcg729, opus, OpenSSL and the `chkstk_ms` placeholder — per platform **and** configuration |
| 3 | `steps\03-pjproject.ps1` | patches and builds the pjproject static library for x64, installs it into `third_party\lib\` |
| 4 | `steps\04-app.ps1` | builds `microsip.vcxproj` |

Run a single step with `-Step`:

```powershell
.\build\build.ps1 -Step check
.\build\build.ps1 -Step prepare
.\build\build.ps1 -Step thirdparty -Platform x64 -Configuration Debug
.\build\build.ps1 -Step pjproject
.\build\build.ps1 -Step app -Platform x64
```

Useful switches: `-Platform x64|Win32|All`, `-Configuration Debug|Release|All`,
`-NoSsl` (skip the OpenSSL/TLS backend), `-BuildSslWin32` (build OpenSSL for
Win32 as well — by default it is x64-only, see §12.5 of `BUILD.md`), `-Force`
(rebuild everything instead of reusing the cached archives).

## Layout

```
build\
  build.ps1          entry point
  steps\             the pipeline
  stub\              chkstk_ms.c - the placeholder archive (see below)
  vs\                the upstream pjproject Visual Studio property sheets
  work\              unpacked sources and intermediate objects (git-ignored)
third_party\         the dependency tree, see third_party\README.md
```

## Things that are easy to get wrong

* **The CRT has to match the configuration.** Debug uses `/MTd`, Release uses
  `/MT`, for *every* third-party archive. Mixing them produces
  `LNK4098: default library 'libcmt.lib' conflicts with other libraries' use`
  — which is only a warning, but means two CRT heaps in one process.
  `steps\02-thirdparty.ps1` therefore builds every archive twice.
* **The shared `third_party\lib` must not contain architecture specific
  archives.** It is searched *before* the per-platform folders, so a 32-bit
  `opus.lib` sitting there wins over the 64-bit one and the x64 build fails
  with unresolved `opus_*` symbols.
* **`chkstk_ms.lib` does not exist for x86/x64.** It is an ARM64-only archive,
  but `microsip.vcxproj` lists it in every configuration. `steps\02-thirdparty.ps1`
  generates a tiny placeholder (see `stub\chkstk_ms.c`) instead.
* **The toolset has to be overridden.** The upstream pjproject property sheet
  hardcodes `v140`, which no longer ships. The pipeline passes
  `/p:BuildToolset=<detected>`; when you open the project in the IDE, set the
  platform toolset by hand.

## Verification

`tools\` holds the verification scripts (they are not part of the pipeline):

```powershell
.\tools\verify-app.ps1 -Exe .\x64\Debug\microsip.exe   # starts the app and checks it
.\tools\verify-openssl.ps1 -Configuration Debug         # static OpenSSL self test
.\tools\verify-tls.ps1 -Configuration Debug              # creates a real SIP-over-TLS transport
.\tools\verify-manifest.ps1                             # checks the vendored archives against their SHA-256
.\tools\verify-pjproject-provenance.ps1                  # checks the headers against upstream
```

See `BUILD.md` for the full story.
