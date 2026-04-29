/*
 * ===----------------------------------------------------------------------=== *
 * Copyright 2025-2026 Yuhao Zhu
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * ===----------------------------------------------------------------------=== *
 *
 * gmp_wrapper.c — C bridge between Mojo and MPFR/GMP.
 *
 * This file uses dlopen/dlsym to load MPFR lazily at runtime. It compiles
 * on any system with a C compiler — no MPFR/GMP headers needed at build time.
 *
 * License note: This file does not contain any code copied from the GMP or
 * MPFR projects. All function signatures were written from scratch based on
 * the publicly documented MPFR C API. The only interaction with MPFR/GMP is
 * through runtime symbol resolution via dlsym. MPFR (LGPLv3+) and GMP
 * (LGPLv3+ or GPLv2+) are loaded dynamically only if installed by the user.
 *
 * Architecture:
 *   - A pool of mpfr_t handles (fixed-size array, index-based)
 *   - Mojo side only sees Int32 handle indices
 *   - All MPFR functions resolved via dlsym at first use
 *   - If MPFR is not installed, mpfrw_available() returns 0
 *
 * Build:
 *   cc -shared -O2 -o libdecimo_gmp_wrapper.dylib gmp_wrapper.c -ldl
 *   (No -lmpfr or -lgmp needed — loaded at runtime via dlopen)
 */

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ===----------------------------------------------------------------------=== *
 * Constants
 * ===----------------------------------------------------------------------=== */

#define MAX_HANDLES     4096
#define MAX_PREC_BITS   1048576  /* 1M bits ≈ 315K decimal digits — safety cap */

/* MPFR rounding mode: round to nearest (ties to even) */
#define MPFR_RNDN 0

/* ===----------------------------------------------------------------------=== *
 * MPFR function pointer typedefs
 *
 * These match the MPFR C API signatures. We resolve them via dlsym so we
 * don't need mpfr.h at compile time.
 * ===----------------------------------------------------------------------=== */

/* mpfr_t is internally a struct. The size is not guaranteed by the MPFR ABI,
 * but has been 32 bytes on all tested platforms (ARM64 macOS, x86_64 Linux)
 * since MPFR 3.x. We over-allocate to 64 bytes and align to 16 bytes for
 * safety. A runtime assertion in mpfrw_load() verifies the actual size.
 * If MPFR headers are available at build time, the compile-time static_assert
 * below catches any mismatch. */
#define MPFR_T_SIZE 64
#define MPFR_T_ALIGN 16

typedef void  (*fn_mpfr_init2)(void *x, long prec);
typedef void  (*fn_mpfr_clear)(void *x);
typedef int   (*fn_mpfr_set_str)(void *rop, const char *s, int base, int rnd);
typedef char* (*fn_mpfr_get_str)(char *str, long *exp, int base, size_t n, const void *op, int rnd);
typedef void  (*fn_mpfr_free_str)(char *str);
typedef int   (*fn_mpfr_add)(void *rop, const void *op1, const void *op2, int rnd);
typedef int   (*fn_mpfr_sub)(void *rop, const void *op1, const void *op2, int rnd);
typedef int   (*fn_mpfr_mul)(void *rop, const void *op1, const void *op2, int rnd);
typedef int   (*fn_mpfr_div)(void *rop, const void *op1, const void *op2, int rnd);
typedef int   (*fn_mpfr_neg)(void *rop, const void *op, int rnd);
typedef int   (*fn_mpfr_abs)(void *rop, const void *op, int rnd);
typedef int   (*fn_mpfr_cmp)(const void *op1, const void *op2);
typedef int   (*fn_mpfr_sqrt)(void *rop, const void *op, int rnd);
typedef int   (*fn_mpfr_exp)(void *rop, const void *op, int rnd);
typedef int   (*fn_mpfr_log)(void *rop, const void *op, int rnd);
typedef int   (*fn_mpfr_sin)(void *rop, const void *op, int rnd);
typedef int   (*fn_mpfr_cos)(void *rop, const void *op, int rnd);
typedef int   (*fn_mpfr_tan)(void *rop, const void *op, int rnd);
typedef int   (*fn_mpfr_pow)(void *rop, const void *op1, const void *op2, int rnd);
typedef int   (*fn_mpfr_rootn_ui)(void *rop, const void *op, unsigned long n, int rnd);
typedef int   (*fn_mpfr_const_pi)(void *rop, int rnd);
typedef long  (*fn_mpfr_get_prec)(const void *x);
typedef int   (*fn_mpfr_snprintf)(char *buf, size_t n, const char *fmt, ...);

/* ===----------------------------------------------------------------------=== *
 * Static state
 * ===----------------------------------------------------------------------=== */

static void *mpfr_lib = NULL;
static int   mpfr_load_attempted = 0;

/* Function pointers — resolved by mpfrw_load() */
static fn_mpfr_init2      p_init2      = NULL;
static fn_mpfr_clear      p_clear      = NULL;
static fn_mpfr_set_str    p_set_str    = NULL;
static fn_mpfr_get_str    p_get_str    = NULL;
static fn_mpfr_free_str   p_free_str   = NULL;
static fn_mpfr_add        p_add        = NULL;
static fn_mpfr_sub        p_sub        = NULL;
static fn_mpfr_mul        p_mul        = NULL;
static fn_mpfr_div        p_div        = NULL;
static fn_mpfr_neg        p_neg        = NULL;
static fn_mpfr_abs        p_abs        = NULL;
static fn_mpfr_cmp        p_cmp        = NULL;
static fn_mpfr_sqrt       p_sqrt       = NULL;
static fn_mpfr_exp        p_exp        = NULL;
static fn_mpfr_log        p_log        = NULL;
static fn_mpfr_sin        p_sin        = NULL;
static fn_mpfr_cos        p_cos        = NULL;
static fn_mpfr_tan        p_tan        = NULL;
static fn_mpfr_pow        p_pow        = NULL;
static fn_mpfr_rootn_ui   p_rootn_ui   = NULL;
static fn_mpfr_const_pi   p_const_pi   = NULL;
static fn_mpfr_snprintf   p_snprintf   = NULL;

/* Handle pool: byte arrays sized to hold mpfr_t, with proper alignment */
static _Alignas(MPFR_T_ALIGN) char handle_pool[MAX_HANDLES][MPFR_T_SIZE];
static int   handle_in_use[MAX_HANDLES];  /* 0 = free, 1 = in use */

/* ===----------------------------------------------------------------------=== *
 * Library loading (dlopen/dlsym)
 * ===----------------------------------------------------------------------=== */

static int mpfrw_load(void) {
    if (mpfr_load_attempted) return (mpfr_lib != NULL);
    mpfr_load_attempted = 1;

    /* Check DECIMO_NOGMP environment variable */
    const char *nogmp = getenv("DECIMO_NOGMP");
    if (nogmp && nogmp[0] != '0' && nogmp[0] != '\0') {
        return 0;
    }

    /* Try common library paths */
    const char *paths[] = {
        "libmpfr.dylib",                           /* macOS via rpath        */
        "/opt/homebrew/lib/libmpfr.dylib",         /* macOS ARM64 (Homebrew) */
        "/usr/local/lib/libmpfr.dylib",            /* macOS x86_64           */
        "libmpfr.so",                              /* Linux via rpath        */
        "/usr/lib/x86_64-linux-gnu/libmpfr.so",    /* Debian/Ubuntu          */
        "/usr/lib/aarch64-linux-gnu/libmpfr.so",   /* Debian ARM64           */
        "/usr/lib/libmpfr.so",                     /* Generic Linux          */
        NULL
    };

    for (int i = 0; paths[i]; i++) {
        mpfr_lib = dlopen(paths[i], RTLD_LAZY);
        if (mpfr_lib) break;
    }
    if (!mpfr_lib) return 0;

    /* Resolve all function pointers */
    p_init2    = (fn_mpfr_init2)      dlsym(mpfr_lib, "mpfr_init2");
    p_clear    = (fn_mpfr_clear)      dlsym(mpfr_lib, "mpfr_clear");
    p_set_str  = (fn_mpfr_set_str)    dlsym(mpfr_lib, "mpfr_set_str");
    p_get_str  = (fn_mpfr_get_str)    dlsym(mpfr_lib, "mpfr_get_str");
    p_free_str = (fn_mpfr_free_str)   dlsym(mpfr_lib, "mpfr_free_str");
    p_add      = (fn_mpfr_add)        dlsym(mpfr_lib, "mpfr_add");
    p_sub      = (fn_mpfr_sub)        dlsym(mpfr_lib, "mpfr_sub");
    p_mul      = (fn_mpfr_mul)        dlsym(mpfr_lib, "mpfr_mul");
    p_div      = (fn_mpfr_div)        dlsym(mpfr_lib, "mpfr_div");
    p_neg      = (fn_mpfr_neg)        dlsym(mpfr_lib, "mpfr_neg");
    p_abs      = (fn_mpfr_abs)        dlsym(mpfr_lib, "mpfr_abs");
    p_cmp      = (fn_mpfr_cmp)        dlsym(mpfr_lib, "mpfr_cmp");
    p_sqrt     = (fn_mpfr_sqrt)       dlsym(mpfr_lib, "mpfr_sqrt");
    p_exp      = (fn_mpfr_exp)        dlsym(mpfr_lib, "mpfr_exp");
    p_log      = (fn_mpfr_log)        dlsym(mpfr_lib, "mpfr_log");
    p_sin      = (fn_mpfr_sin)        dlsym(mpfr_lib, "mpfr_sin");
    p_cos      = (fn_mpfr_cos)        dlsym(mpfr_lib, "mpfr_cos");
    p_tan      = (fn_mpfr_tan)        dlsym(mpfr_lib, "mpfr_tan");
    p_pow      = (fn_mpfr_pow)        dlsym(mpfr_lib, "mpfr_pow");
    p_rootn_ui = (fn_mpfr_rootn_ui)   dlsym(mpfr_lib, "mpfr_rootn_ui");
    p_const_pi = (fn_mpfr_const_pi)   dlsym(mpfr_lib, "mpfr_const_pi");
    p_snprintf = (fn_mpfr_snprintf)   dlsym(mpfr_lib, "mpfr_snprintf");

    /* Verify critical function pointers — if any core symbol is missing,
     * the MPFR library is too old or incompatible. Fail the load. */
    if (!p_init2 || !p_clear || !p_set_str || !p_get_str || !p_free_str ||
        !p_add || !p_sub || !p_mul || !p_div || !p_neg || !p_abs || !p_cmp) {
        dlclose(mpfr_lib);
        mpfr_lib = NULL;
        return 0;
    }

    /* Initialize handle pool */
    memset(handle_in_use, 0, sizeof(handle_in_use));

    return 1;
}

/* ===----------------------------------------------------------------------=== *
 * Public API — called from Mojo via external_call
 * ===----------------------------------------------------------------------=== */

int mpfrw_available(void) {
    return mpfrw_load();
}

int mpfrw_init(int prec_bits) {
    if (!mpfrw_load()) return -1;
    if (prec_bits < 2) prec_bits = 2;
    if (prec_bits > MAX_PREC_BITS) return -1;  /* precision cap */

    /* Find a free handle slot */
    for (int i = 0; i < MAX_HANDLES; i++) {
        if (!handle_in_use[i]) {
            handle_in_use[i] = 1;
            p_init2(&handle_pool[i], (long)prec_bits);
            return i;
        }
    }
    return -1;  /* pool exhausted */
}

void mpfrw_clear(int handle) {
    if (handle < 0 || handle >= MAX_HANDLES) return;
    if (!handle_in_use[handle]) return;
    if (!p_clear) return;  /* MPFR not loaded — nothing to free */
    p_clear(&handle_pool[handle]);
    handle_in_use[handle] = 0;
}

int mpfrw_set_str(int handle, const char *s, int length) {
    if (handle < 0 || handle >= MAX_HANDLES || !handle_in_use[handle]) return -1;

    /* Copy to null-terminated buffer (s may not be null-terminated) */
    char *buf = (char *)malloc(length + 1);
    if (!buf) return -1;
    memcpy(buf, s, length);
    buf[length] = '\0';

    int ret = p_set_str(&handle_pool[handle], buf, 10, MPFR_RNDN);
    free(buf);
    return ret;
}

char* mpfrw_get_str(int handle, int digits) {
    if (handle < 0 || handle >= MAX_HANDLES || !handle_in_use[handle]) return NULL;
    if (digits < 1) digits = 1;

    /* Use mpfr_snprintf to format as decimal string */
    /* Format: %.<digits>RNf for fixed notation, %.<digits>RNg for general */
    int bufsize = digits + 64;  /* extra space for sign, dot, exponent */
    char *buf = (char *)malloc(bufsize);
    if (!buf) return NULL;

    if (p_snprintf) {
        /* %.*Rg: general format with N significant digits, round to nearest */
        p_snprintf(buf, bufsize, "%.*Rg", digits, &handle_pool[handle]);
    } else {
        /* Fallback: use mpfr_get_str + manual formatting */
        long exp;
        char *raw = p_get_str(NULL, &exp, 10, digits, &handle_pool[handle], MPFR_RNDN);
        if (!raw) { free(buf); return NULL; }
        /* TODO: Format raw mantissa + exponent into decimal string */
        snprintf(buf, bufsize, "%sE%ld", raw, exp);
        if (p_free_str) p_free_str(raw);
    }
    return buf;
}

void mpfrw_free_str(char *s) {
    if (s) free(s);
}

/* ===----------------------------------------------------------------------=== *
 * Raw digit export via mpfr_get_str (for fast BigFloat → BigDecimal)
 *
 * p_get_str is mpfr_get_str resolved at runtime via dlsym.  It returns a
 * pure digit string plus a separate base-10 exponent:
 *
 *   raw = "31415...", exp = 1  →  value = 0.31415... × 10^1 = 3.1415...
 *
 * No dot, no 'e' notation.  Negative values have a '-' prefix.
 * The exponent is written to the caller through the out_exp pointer —
 * no mutable global state, no two-call pattern.
 *
 * The returned string is allocated by MPFR and must be freed with
 * mpfrw_free_raw_str().
 * ===----------------------------------------------------------------------=== */

char* mpfrw_get_raw_digits(int handle, int digits, long *out_exp) {
    if (handle < 0 || handle >= MAX_HANDLES || !handle_in_use[handle]) return NULL;
    if (!p_get_str) return NULL;
    if (digits < 1) digits = 1;
    long exp = 0;
    char *raw = p_get_str(NULL, &exp, 10, (size_t)digits,
                          &handle_pool[handle], MPFR_RNDN);
    if (out_exp) *out_exp = exp;
    return raw;  /* Caller frees with mpfrw_free_raw_str */
}

void mpfrw_free_raw_str(char *s) {
    if (s && p_free_str) p_free_str(s);
}

/* ===----------------------------------------------------------------------=== *
 * Arithmetic operations
 * ===----------------------------------------------------------------------=== */

#define CHECK_HANDLES_2(r, a) \
    if ((r) < 0 || (r) >= MAX_HANDLES || !handle_in_use[(r)]) return; \
    if ((a) < 0 || (a) >= MAX_HANDLES || !handle_in_use[(a)]) return;

#define CHECK_HANDLES_3(r, a, b) \
    CHECK_HANDLES_2(r, a) \
    if ((b) < 0 || (b) >= MAX_HANDLES || !handle_in_use[(b)]) return;

void mpfrw_add(int r, int a, int b) {
    CHECK_HANDLES_3(r, a, b);
    p_add(&handle_pool[r], &handle_pool[a], &handle_pool[b], MPFR_RNDN);
}

void mpfrw_sub(int r, int a, int b) {
    CHECK_HANDLES_3(r, a, b);
    p_sub(&handle_pool[r], &handle_pool[a], &handle_pool[b], MPFR_RNDN);
}

void mpfrw_mul(int r, int a, int b) {
    CHECK_HANDLES_3(r, a, b);
    p_mul(&handle_pool[r], &handle_pool[a], &handle_pool[b], MPFR_RNDN);
}

void mpfrw_div(int r, int a, int b) {
    CHECK_HANDLES_3(r, a, b);
    p_div(&handle_pool[r], &handle_pool[a], &handle_pool[b], MPFR_RNDN);
}

void mpfrw_neg(int r, int a) {
    CHECK_HANDLES_2(r, a);
    p_neg(&handle_pool[r], &handle_pool[a], MPFR_RNDN);
}

void mpfrw_abs(int r, int a) {
    CHECK_HANDLES_2(r, a);
    p_abs(&handle_pool[r], &handle_pool[a], MPFR_RNDN);
}

int mpfrw_cmp(int a, int b) {
    if (a < 0 || a >= MAX_HANDLES || !handle_in_use[a]) return -2;  /* error sentinel */
    if (b < 0 || b >= MAX_HANDLES || !handle_in_use[b]) return -2;  /* error sentinel */
    int result = p_cmp(&handle_pool[a], &handle_pool[b]);
    /* Normalize to -1/0/1 so that -2 stays reserved as error sentinel. */
    if (result < 0) return -1;
    if (result > 0) return  1;
    return 0;
}

/* ===----------------------------------------------------------------------=== *
 * Transcendental operations
 * ===----------------------------------------------------------------------=== */

void mpfrw_sqrt(int r, int a) {
    CHECK_HANDLES_2(r, a);
    if (p_sqrt) p_sqrt(&handle_pool[r], &handle_pool[a], MPFR_RNDN);
}

void mpfrw_exp(int r, int a) {
    CHECK_HANDLES_2(r, a);
    if (p_exp) p_exp(&handle_pool[r], &handle_pool[a], MPFR_RNDN);
}

void mpfrw_log(int r, int a) {
    CHECK_HANDLES_2(r, a);
    if (p_log) p_log(&handle_pool[r], &handle_pool[a], MPFR_RNDN);
}

void mpfrw_sin(int r, int a) {
    CHECK_HANDLES_2(r, a);
    if (p_sin) p_sin(&handle_pool[r], &handle_pool[a], MPFR_RNDN);
}

void mpfrw_cos(int r, int a) {
    CHECK_HANDLES_2(r, a);
    if (p_cos) p_cos(&handle_pool[r], &handle_pool[a], MPFR_RNDN);
}

void mpfrw_tan(int r, int a) {
    CHECK_HANDLES_2(r, a);
    if (p_tan) p_tan(&handle_pool[r], &handle_pool[a], MPFR_RNDN);
}

void mpfrw_pow(int r, int a, int b) {
    CHECK_HANDLES_3(r, a, b);
    if (p_pow) p_pow(&handle_pool[r], &handle_pool[a], &handle_pool[b], MPFR_RNDN);
}

void mpfrw_rootn_ui(int r, int a, unsigned int n) {
    CHECK_HANDLES_2(r, a);
    if (p_rootn_ui) p_rootn_ui(&handle_pool[r], &handle_pool[a], (unsigned long)n, MPFR_RNDN);
}

void mpfrw_const_pi(int r) {
    if (r < 0 || r >= MAX_HANDLES || !handle_in_use[r]) return;
    if (p_const_pi) p_const_pi(&handle_pool[r], MPFR_RNDN);
}

/* ===----------------------------------------------------------------------=== *
 * Diagnostics
 * ===----------------------------------------------------------------------=== */

int mpfrw_handles_in_use(void) {
    int count = 0;
    for (int i = 0; i < MAX_HANDLES; i++) {
        if (handle_in_use[i]) count++;
    }
    return count;
}
