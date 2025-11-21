#include <cblas.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "../src/gemm.h"

// Deterministic pseudo-random in [−0.5, 0.5]
static inline float rfloat(unsigned *s)
{
    *s = (*s * 1664525u + 1013904223u);
    return ((float)(*s & 0x00FFFFFF) / (float)0x01000000) - 0.5f;
}

static void fill(float *x, int n, unsigned seed)
{
    for (int i = 0; i < n; ++i)
        x[i] = rfloat(&seed);
}

static void fill_identity(float *x, int n)
{
    memset(x, 0, n * (size_t)n * sizeof(float));
    for (int i = 0; i < n; i++)
        x[i * (size_t)n + i] = 1.0f;
}

static void zero(float *x, int n) { memset(x, 0, n * (size_t)n * sizeof(float)); }

static void ref_sgemm(int n, const float *A, const float *B, float *C)
{
    // C = A*B (alpha=1, beta=0), row-major
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                n, n, n, 1.0f, A, n, B, n, 0.0f, C, n);
}

static int check_close(const float *X, const float *Y, int n,
                       float atol, float rtol, const char *label)
{
    double max_abs = 0.0, max_rel = 0.0;
    int bad_i = -1, bad_j = -1;
    for (int i = 0; i < n; i++)
    {
        for (int j = 0; j < n; j++)
        {
            size_t idx = (size_t)i * n + j;
            float a = X[idx], b = Y[idx];
            double absd = fabs((double)a - (double)b);
            double reld = absd / (fabs((double)b) + 1e-12);
            if (absd > max_abs)
            {
                max_abs = absd;
                bad_i = i;
                bad_j = j;
            }
            if (reld > max_rel)
            {
                max_rel = reld;
            }
            if (!(absd <= atol || reld <= rtol))
            {
                fprintf(stderr,
                        "[FAIL %s] mismatch at (%d,%d): got=%g ref=%g abs=%g rel=%g\n",
                        label, i, j, (double)a, (double)b, absd, reld);
                return 0;
            }
        }
    }
    printf("[OK %s] max_abs=%g max_rel=%g (worst at %d,%d)\n",
           label, max_abs, max_rel, bad_i, bad_j);
    return 1;
}

static int test_case(int n, unsigned seed)
{
    size_t N = (size_t)n * n;
    float *A = aligned_alloc(64, N * 4);
    float *B = aligned_alloc(64, N * 4);
    float *C1 = aligned_alloc(64, N * 4);
    float *C2 = aligned_alloc(64, N * 4);
    float *Cref = aligned_alloc(64, N * 4);

    fill(A, (int)N, seed);
    fill(B, (int)N, seed ^ 0xBADC0DEu);
    zero(C1, n);
    zero(C2, n);
    zero(Cref, n);

    ref_sgemm(n, A, B, Cref);
    gemm_baseline(n, A, B, C1);
    gemm_blocked(n, A, B, C2);

    int ok1 = check_close(C1, Cref, n, /*atol*/ 1e-3f, /*rtol*/ 1e-3f, "baseline");
    int ok2 = check_close(C2, Cref, n, /*atol*/ 1e-3f, /*rtol*/ 1e-3f, "blocked");

    free(A);
    free(B);
    free(C1);
    free(C2);
    free(Cref);
    return ok1 && ok2;
}

static int test_identities(int n)
{
    size_t N = (size_t)n * n;
    float *Id = aligned_alloc(64, N * 4);
    float *A = aligned_alloc(64, N * 4);
    float *C1 = aligned_alloc(64, N * 4);
    float *C2 = aligned_alloc(64, N * 4);
    float *Cref = aligned_alloc(64, N * 4);

    fill_identity(Id, n);

    unsigned seed = 12345u;
    fill(A, (int)N, seed);
    zero(C1, n);
    zero(C2, n);
    zero(Cref, n);

    // A * I == A
    ref_sgemm(n, A, Id, Cref);
    gemm_baseline(n, A, Id, C1);
    gemm_blocked(n, A, Id, C2);
    int okR = check_close(C1, Cref, n, 1e-3f, 1e-3f, "A*I baseline") &&
              check_close(C2, Cref, n, 1e-3f, 1e-3f, "A*I blocked");

    // I * A == A
    zero(C1, n);
    zero(C2, n);
    zero(Cref, n);
    ref_sgemm(n, Id, A, Cref);
    gemm_baseline(n, Id, A, C1);
    gemm_blocked(n, Id, A, C2);
    int okL = check_close(C1, Cref, n, 1e-3f, 1e-3f, "I*A baseline") &&
              check_close(C2, Cref, n, 1e-3f, 1e-3f, "I*A blocked");

    free(Id);
    free(A);
    free(C1);
    free(C2);
    free(Cref);
    return okR && okL;
}

int main(void)
{
    int pass = 1;
    // Small and odd sizes to exercise edges & tails
    int sizes[] = {8, 16, 31, 64};
    for (int s = 0; s < (int)(sizeof(sizes) / sizeof(sizes[0])); ++s)
    {
        int n = sizes[s];
        printf("== correctness n=%d ==\n", n);
        pass &= test_case(n, 0xC0FFEEu ^ (unsigned)n);
    }
    // Identity properties on a few sizes
    pass &= test_identities(16);
    pass &= test_identities(33);

    if (pass)
    {
        puts("ALL UNIT TESTS PASSED");
        return 0;
    }
    else
    {
        puts("UNIT TESTS FAILED");
        return 1;
    }
}
