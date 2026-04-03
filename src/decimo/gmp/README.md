# GMP/MPFR C Wrapper

This directory contains the C wrapper that bridges Mojo to MPFR/GMP via FFI.

## Architecture

The wrapper uses `dlopen`/`dlsym` to load MPFR lazily at **runtime**. This means:

- **Build time**: Only a C compiler is needed. No MPFR/GMP headers or libraries
  are required. The wrapper manually declares `mpfr_t` storage and function pointer
  signatures based on the public MPFR C API.
- **ABI note**: The `mpfr_t` storage is conservatively over-allocated (64 bytes,
  16-byte aligned) to accommodate all known MPFR builds. This has been verified
  on ARM64 macOS and x86_64 Linux. If you encounter issues on an unusual platform,
  rebuilding with `mpfr.h` included would provide a compile-time size check.
- **Runtime**: If MPFR is installed, `mpfrw_available()` returns 1 and all
  operations work. If not installed, it returns 0 and BigFloat raises a clear error.

## Build

```bash
bash src/decimo/gmp/build_gmp_wrapper.sh
```

## Files

- `gmp_wrapper.c` — The C wrapper source. Manages an `mpfr_t` handle pool and
  provides thin wrappers around MPFR functions.
- `build_gmp_wrapper.sh` — Build script for macOS and Linux.
- `libdecimo_gmp_wrapper.dylib` / `.so` — Compiled output (not checked in).

## Installing MPFR

```bash
# macOS (Homebrew)
brew install mpfr

# Linux (Debian/Ubuntu)
sudo apt install libmpfr-dev

# Verify
ls /opt/homebrew/lib/libmpfr.dylib   # macOS ARM64
ls /usr/lib/x86_64-linux-gnu/libmpfr.so  # Linux x86_64
```

## Environment Variables

- `DECIMO_NOGMP=1` — Force-disable MPFR loading even if installed. Useful for testing
  pure-Mojo fallback paths.
