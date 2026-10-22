# AGENTS.md

MicroSIP 3.22.16 — a MFC SIP softphone, packaged so that one clone builds the
executable. The application sources are upstream; everything else in this
repository exists to make `build\build.ps1` work end to end.

## Setup and build commands

There is exactly one supported build path. Do not hand-roll `msbuild`
invocations for third-party libraries — the pipeline handles the CRT, the
include paths and the install layout.

```powershell
.\build\build.ps1                              # everything
.\build\build.ps1 -Step check                  # toolchain check only
.\build\build.ps1 -Step prepare                # unpack + stage + config_site.h
.\build\build.ps1 -Step thirdparty -Platform x64 -Configuration Debug
.\build\build.ps1 -Step pjproject              # the x64 pjproject library
.\build\build.ps1 -Step app -Platform x64
.\build\build.ps1 -Platform x64 -Configuration Release
```

Switches: `-Platform x64|Win32|All`, `-Configuration Debug|Release|All`,
`-NoSsl` (no TLS backend), `-BuildSslWin32`, `-Force` (ignore the cache).

Requirements: Visual Studio 2022/2026 with "Desktop development with C++"
**including MFC**, Windows 10 SDK, Strawberry Perl (OpenSSL), git-lfs.

## Project layout

- `build\` — the pipeline: `build.ps1`, `steps\00-check-toolchain.ps1` … `steps\04-app.ps1`, `stub\chkstk_ms.c`, `vs\` (upstream property sheets)
- `third_party\src\` — source archives, tracked with git-lfs
- `third_party\lib\` — the prebuilt 32-bit pjproject library + the generated x64 ones
- `third_party\pj\`, `third_party\pjsip\`, … — the pjproject headers, flattened (upstream layout)
- `third_party\LICENSES\` — the licence of every vendored dependency
- `tools\` — verification scripts; **not** part of the build
- `BUILD.md` — provenance, measurements, every trap that was solved
- `microsip.vcxproj`, `mainDlg.*` — the application

## Generated files — never edit, never commit

These are produced by the pipeline and are git-ignored:

```
third_party\pj\config_site.h          (written by steps\01-prepare.ps1)
third_party\opus\include\  third_party\bcg729\include\
third_party\SQLiteCpp\SQLiteCpp\  third_party\openssl\
build\work\
```

`pj\config_site.h` is **generated twice** — once for the application
(`third_party\pj\`) and once for the pjproject build tree — and the two files
must stay byte-identical. Change the generator (`steps\01-prepare.ps1`), never
the output.

## Rules that break the build if you ignore them

- **CRT must match the configuration.** Debug uses `/MTd`, Release uses `/MT`,
  for *every* third-party archive. Mixing them yields `LNK4098` plus a set of
  `LNK2019` errors that point at the wrong symbol.
- **Third-party archives live in `third_party\<lib>\<Platform>\<Configuration>\`.**
  The shared `third_party\lib\` is searched *before* the per-platform folders —
  never put an architecture-specific archive there. A 32-bit `opus.lib` there
  breaks the x64 link with unresolved `opus_*` symbols.
- **The Win32 application links the prebuilt 32-bit pjproject library**, which
  has no Opus and no TLS backend. `config_site.h` guards both macros with
  `#if defined(_M_X64)`. OpenSSL is built for x64 only; `Release|Win32` is
  skipped on purpose.
- **The toolset must be overridden.** Upstream's property sheet hardcodes
  `v140`, which no longer ships. The pipeline passes
  `/p:BuildToolset=<detected>` (`v143` / `v145`).
- **`microsip.vcxproj` is CRLF + UTF-8-BOM.** Edit it byte-wise (a script that
  reads and writes raw bytes), never with a text editor that rewrites the
  encoding.

## Testing and verification

There is no unit-test framework. Verification is script based:

```powershell
.\tools\verify-manifest.ps1                                   # SHA-256 of the vendored archives
.\tools\verify-app.ps1 -Exe .\x64\Release\microsip.exe        # starts the app, checks window/threads/db
.\tools\verify-openssl.ps1 -Configuration Debug                # static OpenSSL self test
.\tools\verify-tls.ps1 -Configuration Debug                     # real SIP-over-TLS transport
.\tools\verify-pjproject-provenance.ps1                        # headers vs upstream (needs an upstream checkout)
```

After touching the pipeline or the project file, rebuild **and** run
`verify-app` plus `verify-tls`. A build that links is not proof that the
binary works.

## Code style

- MFC / Win32 C++, MSVC, Unicode
- Match the surrounding file: the application sources use the author's
  formatting, the pipeline scripts use 4-space indent and
  `Write-Ok` / `Write-Note` / `Write-Miss` for step output
- Comments explain *why*, especially around the traps listed above
- Keep `BUILD.md` in sync when a build behaviour changes

## Commits and branches

- Branch from `main`; do not push straight to it
- Conventional commits: `feat:`, `fix:`, `docs:`, `chore:`
- Remotes: `gitee` (`git@gitee.com:wendal/microsip.git`) is the primary one,
  `origin` (`git@github.com:wendal/MicroSIP.git`) is a backup
- The six large files in `third_party\src\` and `third_party\lib\` are
  **git-lfs** objects — keep the `.gitattributes` rules intact

## Security

- Never commit credentials, tokens or `.env` files
- The OpenSSL build uses `no-shared no-module no-tests no-legacy`; the provider
  archives are merged into `libcrypto.lib` so the single
  `#pragma comment(lib, "libcrypto")` in pjlib keeps working
- The executables statically link the CRT and import **no** `msvcrt*.dll` /
  `ucrtbase.dll` — keep it that way (check with `dumpbin /dependents`)
