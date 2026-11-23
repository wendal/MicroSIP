# Third-party licenses

Every dependency vendored in `third_party\` carries its own licence. The
files in this folder are **byte-verbatim copies** taken from the archives in
`third_party\src\`, so what ships here is exactly what upstream ships.

| File | Covers | Licence |
|---|---|---|
| `pjproject-2.17-COPYING.txt` | pjproject 2.17 — the SIP stack, statically linked into the executable | GNU GPL-2.0 (or a commercial licence from Teluu) |
| `openssl-3.0.15-LICENSE.txt` | OpenSSL 3.0.15 — the TLS backend | Apache-2.0 |
| `opus-1.3.1-COPYING.txt` | Opus 1.3.1 — the audio codec | BSD-3-Clause |
| `bcg729-COPYING.txt` | bcg729 — the G.729 codec | GNU GPL-2.0 |
| `SQLiteCpp-3.4.0-LICENSE.txt` | SQLiteCpp 3.4.0 — the C++ SQLite wrapper | MIT |
| `sqlite3-public-domain.txt` | SQLite (the amalgamation bundled inside SQLiteCpp) | public domain |

The pjproject archives the pipeline builds into `third_party\lib\<Platform>\`
are covered by `pjproject-2.17-COPYING.txt`; they are the same upstream
pjproject release, compiled from the vendored source archive (see `BUILD.md`
§9).

## Notes

* **bcg729 is GPL-2.0, not GPL-3.0.** Upstream's `README.md` states "The
  source code is licensed under GPLv2", and the `COPYING` file in the archive
  is the GPL version 2 text. The G.729 patent note in that README is about
  patents, not about the GPL version.
* **SQLite is in the public domain.** The dedication quoted in
  `sqlite3-public-domain.txt` is taken from the amalgamation that SQLiteCpp
  3.4.0 bundles (SQLite 3.53.4).
* **pjproject's own `third_party/` sub-directories** (speex, resample, srtp,
  webrtc, gsm …) carry separate licences inside the upstream release archive.
  Only the pjproject headers are vendored here, not those sources, so their
  licence texts do not apply to this repository — except for libyuv, whose
  sources *are* in the release archive and are compiled into the pjproject
  library the pipeline builds.
* The application itself (everything outside `third_party\`) is **GPL-2.0**;
  see `LICENSE` in the repository root.
