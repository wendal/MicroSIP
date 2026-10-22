# third_party

Everything MicroSIP needs that is not part of its own source.

The layout follows the upstream MicroSIP dependency repository
(`MicroSIP-Com-Deps`) that `microsip.org/source` refers to when it says
*"MicroSIP relies on third-party libraries that are not included in this
repository"*. The pjproject headers are stored flattened, exactly as upstream
stores them.

## What is in here

| Path | Content | Origin |
|---|---|---|
| `pj\`, `pjsip\`, `pjmedia\`, `pjnath\`, `pjlib-util\`, `pjmedia-codec\`, `pjmedia-audiodev\`, `pjmedia-videodev\`, `pjsip-simple\`, `pjsip-ua\`, `pjsua-lib\`, `pjsua2\`, `pj++\` | pjproject 2.14.1 headers, flattened | `MicroSIP-Com-Deps` |
| `*.h`, `*.hpp` at the top level | pjproject convenience headers (`pjlib.h`, `pjsua2.hpp`, …) | `MicroSIP-Com-Deps` |
| `lib\libpjproject-i386-Win32-vc14-Debug-Static.lib` | the prebuilt 32-bit pjproject library | `MicroSIP-Com-Deps` (git-lfs) |
| `src\pjproject-2.14.1.zip` | pjproject source, compiled for x64 | upstream release archive (git-lfs) |
| `src\openssl-3.0.15.zip` | OpenSSL source | upstream release archive (git-lfs) |
| `src\opus-1.3.1.zip` | Opus codec source | upstream release archive (git-lfs) |
| `src\bcg729.zip` | G.729 codec source | upstream archive (git-lfs) |
| `src\SQLiteCpp-3.4.0.zip` | SQLite wrapper source | upstream release archive (git-lfs) |
| `MANIFEST.txt` | SHA-256 of every vendored archive | generated |

The headers were verified to be **byte-identical to upstream pjproject
2.14.1** — `tools\verify-pjproject-provenance.ps1` re-runs that check.

## What is generated (not in git)

`build\steps\01-prepare.ps1` unpacks `src\` into `build\work\` and stages the
headers the compiler needs:

```
third_party\opus\include\opus\*.h          from src\opus-1.3.1.zip
third_party\bcg729\include\bcg729\*.h      from src\bcg729.zip
third_party\SQLiteCpp\sqlite3.h            from src\SQLiteCpp-3.4.0.zip
third_party\SQLiteCpp\SQLiteCpp\*.h        from src\SQLiteCpp-3.4.0.zip
third_party\openssl\Win32\include\openssl\ from src\openssl-3.0.15.zip
third_party\pj\config_site.h                generated feature switches
```

`build\steps\02-thirdparty.ps1` then produces the archives:

```
third_party\lib\<Platform>\chkstk_ms.lib
third_party\SQLiteCpp\<Platform>\<Configuration>\{sqlite3,SQLiteCpp}.lib
third_party\bcg729\<Platform>\<Configuration>\bcg729.lib
third_party\opus\<Platform>\<Configuration>\opus.lib
third_party\openssl\<Platform>\<Configuration>\lib\{libcrypto,libssl}.lib
third_party\lib\libpjproject-x86_64-x64-vc14-<Configuration>-Static.lib
```

The per-platform/per-configuration split is not cosmetic: the static CRT of an
archive has to match the configuration that links it, and the shared
`third_party\lib` folder is searched *before* the per-platform folders.

## Licensing

* pjproject — GPL-2.0 (or a commercial licence from Teluu)
* OpenSSL — Apache-2.0
* Opus — BSD-3-Clause
* bcg729 — see the upstream repository
* SQLiteCpp — MIT (bundles SQLite, public domain)
* MicroSIP itself — GPL-2.0
