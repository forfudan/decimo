/* Times libmpdec directly, with no interpreter in the way.
 *
 * CPython's `decimal` module *is* libmpdec, so timing it from Python measures
 * libmpdec plus interpreter overhead. This links the C library instead, which
 * is the comparison that says something about the arithmetic.
 *
 * Every operation allocates and frees its result, which is what `a + b` does
 * in CPython's `decimal` and what every decimo `BigDecimal` operation does.
 *
 * The in-place section is measured but not rendered into the document. It
 * feeds the note in docs/internal/internal_notes.md about how much of the
 * per-operation cost is allocation.
 *
 * Emits JSON on stdout.
 */

#include <mpdecimal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

/* Must match `build_digits()` in bench_decimo.mojo and `digits()` in
 * bench_python.py exactly, or the three libraries are not being given the same
 * numbers. The multiplier and offset differ by seed. */
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

/* Operand widths paired with the working precision, so that precision grows
 * with the operands instead of rounding almost everything away. */
static const int WIDTHS[] = {9, 1000, 100000, 1000000};
static const int PRECS[] = {28, 1000, 100000, 1000000};
static const long ITERS[] = {200000, 20000, 20, 2};
static const int ROUNDS[] = {7, 7, 3, 3};
#define COMBOS 4

int main(void) {
    double best;
    printf("{\n");
    printf("  \"library\": \"libmpdec\",\n");
    printf("  \"version\": \"%s\",\n", mpd_version());
    printf("  \"bigdecimal\": {\n");

    for (int k = 0; k < COMBOS; k++) {
        int width = WIDTHS[k];
        long iters = ITERS[k];
        int rounds = ROUNDS[k];

        mpd_context_t ctx;
        mpd_maxcontext(&ctx);
        ctx.traps = 0;
        ctx.round = MPD_ROUND_HALF_EVEN;
        ctx.prec = PRECS[k];

        char *dx = make_digits(width, 7);
        char *dy = make_digits(width, 3);
        mpd_t *a = mpd_new(&ctx);
        mpd_t *b = mpd_new(&ctx);
        mpd_t *quantum = mpd_new(&ctx);
        mpd_set_string(a, dx, &ctx);
        mpd_set_string(b, dy, &ctx);
        /* Round away the low half of the operand. Rounding to a fixed ten
         * decimal places is a no-op on a million-digit integer, so the target
         * has to scale with the operand for the row to mean anything. */
        char quantum_text[32];
        snprintf(quantum_text, sizeof(quantum_text), "1E+%d", width / 2);
        mpd_set_string(quantum, quantum_text, &ctx);

        BEST(rounds, iters,
             { mpd_t *r = mpd_new(&ctx); mpd_add(r, a, b, &ctx); mpd_del(r); });
        double v_add = best;
        BEST(rounds, iters,
             { mpd_t *r = mpd_new(&ctx); mpd_sub(r, a, b, &ctx); mpd_del(r); });
        double v_sub = best;
        BEST(rounds, iters,
             { mpd_t *r = mpd_new(&ctx); mpd_mul(r, a, b, &ctx); mpd_del(r); });
        double v_mul = best;
        BEST(rounds, iters,
             { mpd_t *r = mpd_new(&ctx); mpd_div(r, a, b, &ctx); mpd_del(r); });
        double v_div = best;
        BEST(rounds, iters, {
            mpd_t *r = mpd_new(&ctx);
            mpd_quantize(r, a, quantum, &ctx);
            mpd_del(r);
        });
        double v_round = best;
        BEST(rounds, iters, {
            mpd_t *r = mpd_new(&ctx);
            mpd_set_string(r, dx, &ctx);
            mpd_del(r);
        });
        double v_parse = best;

        printf("    \"%d:%d\": {\"add\": %.3f, \"subtract\": %.3f, "
               "\"multiply\": %.3f, \"divide\": %.3f, \"round\": %.3f, "
               "\"from_string\": %.3f}%s\n",
               width, PRECS[k], v_add, v_sub, v_mul, v_div, v_round, v_parse,
               k + 1 < COMBOS ? "," : "");
        fflush(stdout);

        free(dx);
        free(dy);
        mpd_del(a);
        mpd_del(b);
        mpd_del(quantum);
    }
    printf("  },\n");

    /* In place: accumulate into the left operand, matching decimo's
     * `add_inplace()` family. Not rendered; see the file comment. */
    {
        mpd_context_t ctx;
        mpd_maxcontext(&ctx);
        ctx.traps = 0;
        ctx.round = MPD_ROUND_HALF_EVEN;
        ctx.prec = 28;
        mpd_t *a = mpd_new(&ctx);
        mpd_t *b = mpd_new(&ctx);
        mpd_t *acc = mpd_new(&ctx);
        mpd_set_string(a, "12345.6789", &ctx);
        mpd_set_string(b, "9876.54321", &ctx);

        printf("  \"inplace\": {\n");
        mpd_set_string(acc, "12345.6789", &ctx);
        BEST(7, 200000, mpd_add(acc, acc, b, &ctx));
        printf("    \"add\": %.3f,\n", best);
        mpd_set_string(acc, "12345.6789", &ctx);
        BEST(7, 200000, mpd_sub(acc, acc, b, &ctx));
        printf("    \"subtract\": %.3f,\n", best);
        mpd_set_string(acc, "1.0000001", &ctx);
        BEST(7, 200000, mpd_mul(acc, acc, a, &ctx));
        printf("    \"multiply\": %.3f\n", best);
        printf("  },\n");
        mpd_del(a);
        mpd_del(b);
        mpd_del(acc);
    }

    /* sqrt, exp, ln and pow. A fixed set chosen before the results were seen.
     * 100 000 digits is deliberately absent: `mpd_exp` needs 82 seconds there
     * and `mpd_ln` 239 seconds, which is too slow to put in a routine run. */
    {
        static const int HIGHER_PRECS[] = {28, 100, 1000, 10000};
        static const long HIGHER_ITERS[] = {20000, 5000, 200, 1};
        static const int HIGHER_ROUNDS[] = {7, 7, 3, 1};
        printf("  \"higher\": {\n");
        for (int k = 0; k < 4; k++) {
            mpd_context_t hc;
            mpd_maxcontext(&hc);
            hc.traps = 0;
            hc.round = MPD_ROUND_HALF_EVEN;
            hc.prec = HIGHER_PRECS[k];
            mpd_t *x = mpd_new(&hc);
            mpd_t *y = mpd_new(&hc);
            mpd_set_string(x, "2.3456789", &hc);
            mpd_set_string(y, "1.5", &hc);
            long it = HIGHER_ITERS[k];
            int rd = HIGHER_ROUNDS[k];

            BEST(rd, it,
                 { mpd_t *r = mpd_new(&hc); mpd_sqrt(r, x, &hc); mpd_del(r); });
            double h_sqrt = best;
            BEST(rd, it,
                 { mpd_t *r = mpd_new(&hc); mpd_exp(r, x, &hc); mpd_del(r); });
            double h_exp = best;
            BEST(rd, it,
                 { mpd_t *r = mpd_new(&hc); mpd_ln(r, x, &hc); mpd_del(r); });
            double h_ln = best;
            BEST(rd, it, {
                mpd_t *r = mpd_new(&hc);
                mpd_pow(r, x, y, &hc);
                mpd_del(r);
            });
            double h_pow = best;

            printf("    \"%d\": {\"sqrt\": %.3f, \"exp\": %.3f, \"ln\": %.3f, "
                   "\"power\": %.3f}%s\n",
                   HIGHER_PRECS[k], h_sqrt, h_exp, h_ln, h_pow,
                   k + 1 < 4 ? "," : "");
            fflush(stdout);
            mpd_del(x);
            mpd_del(y);
        }
        printf("  },\n");
    }

    /* Digest of a 1000-digit product, so the generator can confirm that decimo
     * and libmpdec computed the same number rather than assuming it. */
    {
        mpd_context_t big;
        mpd_maxcontext(&big);
        big.traps = 0;
        char *dx = make_digits(1000, 7);
        char *dy = make_digits(1000, 3);
        mpd_t *x = mpd_new(&big);
        mpd_t *y = mpd_new(&big);
        mpd_t *pr = mpd_new(&big);
        mpd_set_string(x, dx, &big);
        mpd_set_string(y, dy, &big);
        mpd_mul(pr, x, y, &big);
        char *text = mpd_to_sci(pr, 1);
        size_t n = strlen(text);
        printf("  \"sweep_digest\": {\"digits\": %zu, \"tail\": \"%s\"}\n", n,
               n >= 24 ? text + n - 24 : text);
        mpd_free(text);
        mpd_del(x);
        mpd_del(y);
        mpd_del(pr);
        free(dx);
        free(dy);
    }

    printf("}\n");
    return 0;
}
