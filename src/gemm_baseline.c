#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <omp.h>
#include "gemm.h"

void gemm_baseline(int n, const float *A, const float *B, float *C)
{
#pragma omp parallel for
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            float sum = 0.0f;
            for (int k = 0; k < n; k++) {
                sum += A[i * (size_t)n + k] * B[k * (size_t)n + j];
            }
            C[i * (size_t)n + j] = sum;
        }
    }
}

#ifndef GEMM_NO_MAIN
static double now()
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

static void* xaligned64(size_t bytes) {
  void* p = NULL;
  int rc = posix_memalign(&p, 64, bytes);
  if (rc != 0 || p == NULL) {
      fprintf(stderr, "posix_memalign(64, %zu) failed (rc=%d)\n", bytes, rc);
      exit(1);
  }
  return p;
}

int main(int argc, char **argv)
{
    int n = (argc > 1) ? atoi(argv[1]) : 1024;
    size_t bytes = (size_t)n * n * sizeof(float);

    float *A = xaligned64(bytes);
    float *B = xaligned64(bytes);
    float *C = xaligned64(bytes);

    for (size_t i = 0; i < (size_t)n * n; i++) {
        A[i] = 1.f;
        B[i] = 1.f;
        C[i] = 0.f;
    }

    gemm_baseline(n, A, B, C);
    double t0 = now();
    gemm_baseline(n, A, B, C);
    double t1 = now();

    double flops = 2.0 * (double)n * n * n;
    printf("n=%d time=%.6f s GFLOP/s=%.2f\n", n, (t1 - t0), flops / (t1 - t0) / 1e9);

    free(C);
    free(B);
    free(A);
    return 0;
}
#endif
