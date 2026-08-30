# GMP/MPFR C Wrapper

This directory contains the C wrapper that bridges Mojo to MPFR/GMP via FFI.

## Architecture

The wrapper uses `dlopen`/`dlsym` to load MPFR lazily at **runtime**. This
means:

- **Build time**: Only a C compiler is needed. No MPFR/GMP headers or libraries
  are required. The wrapper manually declares `mpfr_t` storage and function
  pointer signatures based on the public MPFR C API.
- **ABI note**: The `mpfr_t` storage is conservatively over-allocated (64 bytes,
  16-byte aligned) to accommodate all known MPFR builds. This has been verified
  on ARM64 macOS and x86_64 Linux. If you encounter issues on an unusual
  platform, rebuilding with `mpfr.h` included would provide a compile-time size
  check.
- **Runtime**: If MPFR is installed, `mpfrw_available()` returns 1 and all
  operations work. If not installed, it returns 0 and BigFloat raises a clear
  error.

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

## Cross-platform notes

The wrapper is built by `build_gmp_wrapper.sh`, which handles the two
differences between the platforms:

- **macOS.** `cc -shared -O2` produces a `.dylib`, and `install_name_tool -id
  @rpath/libdecimo_gmp_wrapper.dylib` sets the install name so the loader finds
  it through the executable's rpath. Without that step the library resolves
  only from the directory it was built in.
- **Linux.** `cc -shared -O2 -fPIC` produces a `.so`, and `-ldl` is required
  because `dlopen` and `dlsym` live in `libdl` there rather than in libc.

Nothing else is platform-specific: the wrapper declares MPFR's storage and
signatures itself, so no headers are needed at build time on either system.

## Traps

These cost real debugging time. They are recorded here rather than in a plan
document because they are properties of this wrapper.

### A Mojo `String` passed to `external_call` can be freed before the call reads it

Writing `external_call[..., Int](h, Int(s.unsafe_ptr()))` lets the optimizer
drop `s` before the call runs. Under allocation pressure the freed buffer is
reused immediately and the null terminator is overwritten, so the C side reads
past the end of the string. The symptom is a failure that appears only in long
benchmark runs and never in a small test file.

The fix is to pass the length explicitly and copy on the C side, which is why
`gmpw_set_str_n` takes a length rather than relying on null termination. Take
the length *before* taking the pointer:

```mojo
var slen = c_int(len(s))          # length first
var ptr = Int(s.unsafe_ptr())
_ = external_call["gmpw_set_str_n", c_int, c_int, Int, c_int](h, ptr, slen)
```

This applies to every FFI call that hands a Mojo `String` to C, not just this
wrapper.

### `mojo run` ignores `-Xlinker`

The JIT does not process linker flags, so a `mojo run file.mojo -Xlinker ...`
silently links nothing. Use `mojo build` and run the resulting executable.

### GMP's `__gmp_overflow_in_mpz` means bad input, not overflow

The name suggests a size limit. It is raised when the string handed to
`mpz_set_str` contains a character that is not a digit in the given base, which
in practice means the string was truncated or corrupted before it arrived --
usually the lifetime problem above.

### Debugging the wrapper

The C side is invisible from Mojo's debugger. Adding `fprintf(stderr, ...)`
inside `gmp_wrapper.c` and rebuilding is the quickest way to see what the
wrapper actually received; that is how the string-lifetime bug above was
identified, by printing `strlen()` of the incoming pointer and comparing it
with the length Mojo believed it had sent.

## Environment Variables

- `DECIMO_NOGMP=1` — Force-disable MPFR loading even if installed. Useful for
  testing the error `BigFloat` raises when MPFR is not there.
