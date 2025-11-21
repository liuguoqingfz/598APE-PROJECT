#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include "../src/gemm.h"

static double now()
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

static void fill(float *x, size_t n)
{
    for (size_t i = 0; i < n; i++)
        x[i] = (float)(i % 13) * 0.01f;
}

static double run_once(const char *which, int n)
{
    size_t N = (size_t)n * n;
    float *A = aligned_alloc(64, N * 4), *B = aligned_alloc(64, N * 4), *C = aligned_alloc(64, N * 4);
    fill(A, N);
    fill(B, N);
    memset(C, 0, N * 4);

    // warmup
    if (strcmp(which, "baseline") == 0)
        gemm_baseline(n, A, B, C);
    else
        gemm_blocked(n, A, B, C);

    double t0 = now();
    if (strcmp(which, "baseline") == 0)
        gemm_baseline(n, A, B, C);
    else
        gemm_blocked(n, A, B, C);
    double t1 = now();

    free(A);
    free(B);
    free(C);
    return t1 - t0;
}

int main(int argc, char **argv)
{
    if (argc < 4)
    {
        fprintf(stderr, "Usage: %s <baseline|blocked> <n> <trials>\n", argv[0]);
        return 2;
    }
    const char *which = argv[1];
    int n = atoi(argv[2]);
    int trials = atoi(argv[3]);

    // CSV header to stdout (append rows in your script)
    // variant,n,threads,flops,time_s,gflops,date
    for (int t = 0; t < trials; t++)
    {
        double time_s = run_once(which, n);
        double flops = 2.0 * (double)n * n * n;
        double gflops = flops / time_s / 1e9;
        printf("%s,%d,%d,%.0f,%.6f,%.3f,%ld\n",
               which, n, 4, flops, time_s, gflops, (long)time(NULL));
        fflush(stdout);
    }
    return 0;
}
