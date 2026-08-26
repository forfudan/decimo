/* Times libmpdec directly, with no interpreter in the way.
 *
 * CPython's `decimal` module *is* libmpdec, so timing it from Python measures
 * libmpdec plus interpreter overhead. This links the C library instead, which
 * is the comparison that says something about the arithmetic.
 *
 * Two modes, both of which correspond to something a user actually writes:
 *
 *   "fresh"    allocates and frees the result every iteration, which is what
 *              `a + b` does in CPython's `decimal` and what every decimo
 *              `BigDecimal` operation does.
 *   "inplace"  accumulates into the left operand, matching decimo's
 *              `add_inplace()` family.
 *
 * Emits JSON on stdout.
 *
 * Build:
 *   cc -O2 -I<prefix>/include -L<prefix>/lib -lmpdec bench_libmpdec.c -o ...
 */

#include <mpdecimal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define ROUNDS 7
#define ITERS 200000

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

/* Minimum over ROUNDS: noise on a latency benchmark is one-sided. */
#define BEST(body)                                                   \
    do {                                                             \
        best = 1e30;                                                 \
        for (int r = 0; r < ROUNDS; r++) {                           \
            double t0 = now_ns();                                    \
            for (long i = 0; i < ITERS; i++) {                       \
                body;                                                \
            }                                                        \
            double per = (now_ns() - t0) / (double)ITERS;            \
            if (per < best) best = per;                              \
        }                                                            \
    } while (0)

int main(void) {
    mpd_context_t ctx;
    mpd_init(&ctx, 28);
    ctx.traps = 0;

    mpd_t *a = mpd_new(&ctx);
    mpd_t *b = mpd_new(&ctx);
    mpd_t *acc = mpd_new(&ctx);
    mpd_t *wide = mpd_new(&ctx);
    /* Rounding target: 1e-10, so `mpd_quantize` rounds to ten decimal places
     * -- the same thing decimo's `round(x, 10, HALF_EVEN)` does. Rounding to
     * an integer instead would compare two different operations. */
    mpd_t *quantum = mpd_new(&ctx);
    mpd_set_string(a, "12345.6789", &ctx);
    mpd_set_string(b, "9876.54321", &ctx);
    mpd_set_string(wide, "1234.56789012345678901234567890", &ctx);
    mpd_set_string(quantum, "1E-10", &ctx);
    ctx.round = MPD_ROUND_HALF_EVEN;

    double best;
    printf("{\n");
    printf("  \"library\": \"libmpdec\",\n");
    printf("  \"version\": \"%s\",\n", mpd_version());
    printf("  \"rounds\": %d,\n", ROUNDS);
    printf("  \"iterations\": %d,\n", ITERS);
    printf("  \"fresh\": {\n");

    BEST({ mpd_t *r = mpd_new(&ctx); mpd_add(r, a, b, &ctx); mpd_del(r); });
    printf("    \"add\": %.3f,\n", best);
    BEST({ mpd_t *r = mpd_new(&ctx); mpd_sub(r, a, b, &ctx); mpd_del(r); });
    printf("    \"subtract\": %.3f,\n", best);
    BEST({ mpd_t *r = mpd_new(&ctx); mpd_mul(r, a, b, &ctx); mpd_del(r); });
    printf("    \"multiply\": %.3f,\n", best);
    BEST({ mpd_t *r = mpd_new(&ctx); mpd_div(r, a, b, &ctx); mpd_del(r); });
    printf("    \"divide\": %.3f,\n", best);
    BEST({
        mpd_t *r = mpd_new(&ctx);
        mpd_quantize(r, wide, quantum, &ctx);
        mpd_del(r);
    });
    printf("    \"round\": %.3f,\n", best);
    BEST({
        mpd_t *r = mpd_new(&ctx);
        mpd_set_string(r, "12345.6789", &ctx);
        mpd_del(r);
    });
    printf("    \"from_string\": %.3f\n", best);
    printf("  },\n");
    /* --- In-place accumulation ----------------------------------------- *
     * The fair counterpart to decimo's `add_inplace()` family. "reuse" above
     * writes `a + b` into a result allocated once, with both operands fixed;
     * decimo's in-place calls accumulate into their left operand. Those are
     * different operations, so this section does exactly what decimo does --
     * same starting values, same operand, same precision -- and only these
     * numbers should be set against decimo's in-place column.               */
    printf("  \"inplace\": {\n");
    {
        mpd_t *acc = mpd_new(&ctx);
        mpd_set_string(acc, "12345.6789", &ctx);
        BEST(mpd_add(acc, acc, b, &ctx));
        printf("    \"add\": %.3f,\n", best);
        mpd_set_string(acc, "12345.6789", &ctx);
        BEST(mpd_sub(acc, acc, b, &ctx));
        printf("    \"subtract\": %.3f,\n", best);
        mpd_set_string(acc, "1.0000001", &ctx);
        BEST(mpd_mul(acc, acc, a, &ctx));
        printf("    \"multiply\": %.3f\n", best);
        mpd_del(acc);
    }
    printf("  },\n");

    /* --- Higher-level operations ---------------------------------------- *
     * sqrt, exp, ln and pow, at three precisions. Fixed set, chosen before
     * the results were seen, and all four reported either way.              */
    {
        static const int PRECS[] = {28, 100, 1000};
        mpd_t *sx = mpd_new(&ctx), *sy = mpd_new(&ctx);
        printf("  \"higher\": {\n");
        for (size_t k = 0; k < sizeof(PRECS) / sizeof(PRECS[0]); k++) {
            mpd_context_t hc;
            mpd_maxcontext(&hc);
            hc.traps = 0;
            hc.round = MPD_ROUND_HALF_EVEN;
            hc.prec = PRECS[k];
            mpd_set_string(sx, "2.3456789", &hc);
            mpd_set_string(sy, "1.5", &hc);

            long it = PRECS[k] >= 1000 ? 200L : (PRECS[k] >= 100 ? 5000L : 20000L);
            int rd = PRECS[k] >= 1000 ? 3 : ROUNDS;
            double bx;
#define HI(body)                                                     \
            do {                                                     \
                bx = 1e30;                                           \
                for (int r = 0; r < rd; r++) {                       \
                    double t0 = now_ns();                            \
                    for (long i = 0; i < it; i++) { body; }          \
                    double per = (now_ns() - t0) / (double)it;       \
                    if (per < bx) bx = per;                          \
                }                                                    \
            } while (0)
            HI({ mpd_t *r = mpd_new(&hc); mpd_sqrt(r, sx, &hc); mpd_del(r); });
            double h_sqrt = bx;
            HI({ mpd_t *r = mpd_new(&hc); mpd_exp(r, sx, &hc); mpd_del(r); });
            double h_exp = bx;
            HI({ mpd_t *r = mpd_new(&hc); mpd_ln(r, sx, &hc); mpd_del(r); });
            double h_ln = bx;
            HI({ mpd_t *r = mpd_new(&hc); mpd_pow(r, sx, sy, &hc); mpd_del(r); });
            double h_pow = bx;
#undef HI
            printf("    \"%d\": {\"sqrt\": %.3f, \"exp\": %.3f, "
                   "\"ln\": %.3f, \"power\": %.3f}%s\n",
                   PRECS[k], h_sqrt, h_exp, h_ln, h_pow,
                   k + 1 < sizeof(PRECS) / sizeof(PRECS[0]) ? "," : "");
        }
        printf("  },\n");
        mpd_del(sx); mpd_del(sy);
    }

    /* --- Operand-size sweep -------------------------------------------- *
     * The numbers above are one base-10^9 word each, which is the extreme
     * small end and says nothing about how either library scales. libmpdec
     * switches to a number-theoretic transform for large coefficients, and so
     * does decimo, so the interesting question is where the crossovers are.
     * Exact arithmetic here (context precision above the result width), so
     * nothing is rounded away.                                              */
    mpd_context_t big;
    mpd_maxcontext(&big);
    big.traps = 0;
    big.round = MPD_ROUND_HALF_EVEN;

    /* Division needs a finite target precision; the rest is exact. Built once
     * -- `mpd_init` warns if called repeatedly, since it also tries to set the
     * global MPD_MINALLOC each time. */
    mpd_context_t divctx;
    mpd_maxcontext(&divctx);
    divctx.traps = 0;
    divctx.round = MPD_ROUND_HALF_EVEN;

    static const int WIDTHS[] = {9, 100, 1000, 10000, 100000};
    printf("  \"sweep\": {\n");
    for (size_t w = 0; w < sizeof(WIDTHS) / sizeof(WIDTHS[0]); w++) {
        int width = WIDTHS[w];
        char *dx = malloc((size_t)width + 1);
        char *dy = malloc((size_t)width + 1);
        int sx = 7, sy = 3;
        for (int i = 0; i < width; i++) {
            sx = (sx * 31 + 17) % 9;
            dx[i] = (char)('1' + sx);
            sy = (sy * 37 + 11) % 9;
            dy[i] = (char)('1' + sy);
        }
        dx[width] = dy[width] = '\0';

        mpd_t *x = mpd_new(&big), *y = mpd_new(&big);
        mpd_set_string(x, dx, &big);
        mpd_set_string(y, dy, &big);

        long iters = 2000000L / width;
        if (iters < 3) iters = 3;
        int rounds = width >= 10000 ? 3 : ROUNDS;
        double bx;

#define SWEEP(body)                                                  \
        do {                                                         \
            bx = 1e30;                                               \
            for (int r = 0; r < rounds; r++) {                       \
                double t0 = now_ns();                                \
                for (long i = 0; i < iters; i++) { body; }           \
                double per = (now_ns() - t0) / (double)iters;        \
                if (per < bx) bx = per;                              \
            }                                                        \
        } while (0)

        SWEEP({ mpd_t *r = mpd_new(&big); mpd_add(r, x, y, &big); mpd_del(r); });
        double s_add = bx;
        SWEEP({ mpd_t *r = mpd_new(&big); mpd_mul(r, x, y, &big); mpd_del(r); });
        double s_mul = bx;
        divctx.prec = width + 8;
        SWEEP({ mpd_t *r = mpd_new(&divctx); mpd_div(r, x, y, &divctx); mpd_del(r); });
        double s_div = bx;
#undef SWEEP

        printf("    \"%d\": {\"add\": %.3f, \"multiply\": %.3f, \"divide\": %.3f}%s\n",
               width, s_add, s_mul, s_div,
               w + 1 < sizeof(WIDTHS) / sizeof(WIDTHS[0]) ? "," : "");
        mpd_del(x); mpd_del(y); free(dx); free(dy);
    }
    printf("  },\n");

    /* Digest of the same 1000-digit product decimo reports, so the generator
     * can confirm both sides computed the same number. Without it, "exact on
     * both sides" is an assumption rather than a check. */
    {
        char *dx = malloc(1001), *dy = malloc(1001);
        int sx2 = 7, sy2 = 3;
        for (int i = 0; i < 1000; i++) {
            sx2 = (sx2 * 31 + 17) % 9; dx[i] = (char)('1' + sx2);
            sy2 = (sy2 * 37 + 11) % 9; dy[i] = (char)('1' + sy2);
        }
        dx[1000] = dy[1000] = '\0';
        mpd_t *x = mpd_new(&big), *y = mpd_new(&big), *pr = mpd_new(&big);
        mpd_set_string(x, dx, &big);
        mpd_set_string(y, dy, &big);
        mpd_mul(pr, x, y, &big);
        char *text = mpd_to_sci(pr, 1);
        size_t n = strlen(text);
        printf("  \"sweep_digest\": {\"digits\": %zu, \"tail\": \"%s\"}\n",
               n, n >= 24 ? text + n - 24 : text);
        mpd_free(text);
        mpd_del(x); mpd_del(y); mpd_del(pr);
        free(dx); free(dy);
    }
    printf("}\n");

    mpd_del(a);
    mpd_del(b);
    mpd_del(acc);
    mpd_del(wide);
    mpd_del(quantum);
    return 0;
}
