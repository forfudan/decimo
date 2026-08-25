/* Times libmpdec directly, with no interpreter in the way.
 *
 * CPython's `decimal` module *is* libmpdec, so timing it from Python measures
 * libmpdec plus interpreter overhead. This links the C library instead, which
 * is the comparison that says something about the arithmetic.
 *
 * Each operation is measured two ways:
 *
 *   "fresh"  allocates and frees the result every iteration, which is what
 *            decimo does -- every `BigDecimal` operation returns a new value.
 *            This is the number to compare against.
 *   "reuse"  writes into a result allocated once, which is what tight C code
 *            does. It is reported to show how much of the cost is allocation.
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
    printf("  \"reuse\": {\n");

    BEST(mpd_add(acc, a, b, &ctx));
    printf("    \"add\": %.3f,\n", best);
    BEST(mpd_sub(acc, a, b, &ctx));
    printf("    \"subtract\": %.3f,\n", best);
    BEST(mpd_mul(acc, a, b, &ctx));
    printf("    \"multiply\": %.3f,\n", best);
    BEST(mpd_div(acc, a, b, &ctx));
    printf("    \"divide\": %.3f,\n", best);
    BEST(mpd_quantize(acc, wide, quantum, &ctx));
    printf("    \"round\": %.3f,\n", best);
    BEST(mpd_set_string(acc, "12345.6789", &ctx));
    printf("    \"from_string\": %.3f\n", best);
    printf("  }\n}\n");

    mpd_del(a);
    mpd_del(b);
    mpd_del(acc);
    mpd_del(wide);
    mpd_del(quantum);
    return 0;
}
