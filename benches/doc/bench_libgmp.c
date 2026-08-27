/* Times GMP's integers directly, with no interpreter in the way.
 *
 * `gmpy2` is a thin wrapper over GMP, so timing it from Python measures GMP
 * plus interpreter overhead. This links the C library instead, which is the
 * comparison that says something about the arithmetic. GMP is the reference
 * implementation for big integers; it is a harder opponent than CPython's
 * `int`, and it is the one decimo's `BigInt` should be measured against.
 *
 * Every operation initialises and clears its result, which is what every
 * decimo `BigInt` operation does. GMP's own idiom is to reuse a result across
 * a loop, so the same operations are timed that way too; the difference is
 * the allocator, and it is reported separately rather than folded in.
 *
 * Emits JSON on stdout.
 */

#include <gmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

/* Minimum over `rounds`: noise on a latency benchmark is one-sided. */
#define BEST(rounds, iters, body)                                    \
    do {                                                             \
        best = 1e30;                                                 \
        for (int r_ = 0; r_ < (rounds); r_++) {                      \
            double t0_ = now_ns();                                   \
            for (long i_ = 0; i_ < (iters); i_++) {                  \
                body;                                                \
            }                                                        \
            double per_ = (now_ns() - t0_) / (double)(iters);        \
            if (per_ < best) best = per_;                            \
        }                                                            \
    } while (0)

/* Must match `build_digits()` in bench_decimo.mojo exactly, or the two
 * libraries are not being given the same numbers. */
static char *make_digits(int count, int seed) {
    char *out = malloc((size_t)count + 1);
    int step = seed == 7 ? 31 : 37;
    int offset = seed == 7 ? 17 : 11;
    int state = seed;
    for (int i = 0; i < count; i++) {
        state = (state * step + offset) % 9;
        out[i] = (char)('1' + state);
    }
    out[count] = '\0';
    return out;
}

/* The same widths and iteration counts as the `BigInt` section of
 * bench_decimo.mojo. */
static const int WIDTHS[] = {10, 100, 1000, 10000, 100000, 1000000};
static const long ITERS[] = {200000, 20000, 5000, 200, 20, 2};
static const int ROUNDS[] = {7, 7, 7, 5, 3, 3};
#define COMBOS 6

int main(void) {
    double best;
    printf("{\n");
    printf("  \"library\": \"libgmp\",\n");
    printf("  \"version\": \"%s\",\n", gmp_version);
    printf("  \"bigint\": {\n");

    for (int k = 0; k < COMBOS; k++) {
        int width = WIDTHS[k];
        long iters = ITERS[k];
        int rounds = ROUNDS[k];

        char *dx = make_digits(width, 7);
        char *dy = make_digits(width, 3);
        mpz_t a, b, wide;
        mpz_init_set_str(a, dx, 10);
        mpz_init_set_str(b, dy, 10);
        /* A 2n-by-n division. Dividing two operands of the same width gives a
         * one-word quotient and measures nothing. */
        mpz_init(wide);
        mpz_mul(wide, a, b);

        BEST(rounds, iters,
             { mpz_t r; mpz_init(r); mpz_add(r, a, b); mpz_clear(r); });
        double v_add = best;
        BEST(rounds, iters,
             { mpz_t r; mpz_init(r); mpz_mul(r, a, b); mpz_clear(r); });
        double v_mul = best;
        BEST(rounds, iters,
             { mpz_t r; mpz_init(r); mpz_fdiv_q(r, wide, b); mpz_clear(r); });
        double v_div = best;
        BEST(rounds, iters,
             { mpz_t r; mpz_init(r); mpz_sqrt(r, a); mpz_clear(r); });
        double v_sqrt = best;
        printf("    \"%d\": {\"add\": %.3f, \"multiply\": %.3f, "
               "\"floor_divide\": %.3f, \"sqrt\": %.3f}%s\n",
               width, v_add, v_mul, v_div, v_sqrt,
               k + 1 < COMBOS ? "," : "");
        fflush(stdout);

        free(dx);
        free(dy);
        mpz_clear(a);
        mpz_clear(b);
        mpz_clear(wide);
    }
    printf("  },\n");

    /* Reusing one result across the loop, which is GMP's own idiom: after the
     * first iteration the destination is already wide enough and the
     * allocator is never called. The gap against the section above is what
     * decimo pays per operation for allocating a fresh result. */
    printf("  \"bigint_reused\": {\n");
    for (int k = 0; k < COMBOS; k++) {
        int width = WIDTHS[k];
        long iters = ITERS[k];
        int rounds = ROUNDS[k];

        char *dx = make_digits(width, 7);
        char *dy = make_digits(width, 3);
        mpz_t a, b, wide, r;
        mpz_init_set_str(a, dx, 10);
        mpz_init_set_str(b, dy, 10);
        mpz_init(wide);
        mpz_mul(wide, a, b);
        mpz_init(r);

        BEST(rounds, iters, { mpz_add(r, a, b); });
        double v_add = best;
        BEST(rounds, iters, { mpz_mul(r, a, b); });
        double v_mul = best;
        BEST(rounds, iters, { mpz_fdiv_q(r, wide, b); });
        double v_div = best;
        BEST(rounds, iters, { mpz_sqrt(r, a); });
        double v_sqrt = best;

        printf("    \"%d\": {\"add\": %.3f, \"multiply\": %.3f, "
               "\"floor_divide\": %.3f, \"sqrt\": %.3f}%s\n",
               width, v_add, v_mul, v_div, v_sqrt,
               k + 1 < COMBOS ? "," : "");
        fflush(stdout);

        free(dx);
        free(dy);
        mpz_clear(a);
        mpz_clear(b);
        mpz_clear(wide);
        mpz_clear(r);
    }
    printf("  }\n");
    printf("}\n");
    return 0;
}
