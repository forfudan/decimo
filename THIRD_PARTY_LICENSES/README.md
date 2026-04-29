# THIRD_PARTY_LICENSES

This directory contains the full text of the licenses that govern the
third-party components bundled into the pre-built `decimo` CLI binary
distributed via the [`forfudan/tap`](https://github.com/forfudan/homebrew-tap)
Homebrew tap and the corresponding GitHub release tarballs.

These files are vendored in the repository so that the contents of the
release tarballs are deterministic and reproducible — the CI workflow
copies them verbatim instead of fetching them at build time.

| File                                | Applies to                                                                                                                                                                       |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MODULAR_COMMUNITY_LICENSE.txt`     | Mojo SDK runtime libraries (`libKGENCompilerRTShared`, `libAsyncRTMojoBindings`, `libAsyncRTRuntimeGlobals`, `libMSupportGlobals`, `libNVPTX`) bundled in every release tarball. |
| `GCC_RUNTIME_LIBRARY_EXCEPTION.txt` | `libstdc++.so.6` and `libgcc_s.so.1` bundled in the **Linux x86_64** release tarball only.                                                                                       |

The Decimo source code itself is licensed under Apache-2.0; see
[`LICENSE`](../LICENSE) and [`NOTICE`](../NOTICE) at the repository
root.

## Updating the vendored texts

If the upstream license texts change, replace the affected file with
a fresh plain-text snapshot fetched from the canonical source:

- Modular Community License: <https://www.modular.com/legal/community>
- GCC Runtime Library Exception 3.1: <https://www.gnu.org/licenses/gcc-exception-3.1.html>

Then bump the relevant version/date noted at the top of the file and
trigger a new release build.
