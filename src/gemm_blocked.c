#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <omp.h>
#include "gemm.h"
#ifndef MB
#define MB 96
#endif
#ifndef NB
#define NB 96
#endif
#ifndef KB
#define KB 256
#endif

static double now()
{
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec * 1e-9;
}

void gemm_blocked(int n, const float *A, const float *B, float *C)
{
#pragma omp parallel for collapse(2) schedule(static)
  for (int ii = 0; ii < n; ii += MB)
  {
    for (int jj = 0; jj < n; jj += NB)
    {
      int iimax = (ii + MB > n) ? n : ii + MB;
      int jjmax = (jj + NB > n) ? n : jj + NB;
      for (int kk = 0; kk < n; kk += KB)
      {
        int kkmax = (kk + KB > n) ? n : kk + KB;
        for (int i = ii; i < iimax; ++i)
        {
          for (int j = jj; j < jjmax; ++j)
          {
            float sum = (kk == 0) ? 0.f : C[i * (size_t)n + j];
            for (int k = kk; k < kkmax; ++k)
            {
              sum += A[i * (size_t)n + k] * B[k * (size_t)n + j];
            }
            C[i * (size_t)n + j] = sum;
          }
        }
      }
    }
  }
}

#ifndef GEMM_NO_MAIN
int main(int argc, char **argv)
{
  int n = (argc > 1) ? atoi(argv[1]) : 1024;
  size_t bytes = (size_t)n * n * sizeof(float);
  float *A = aligned_alloc(64, bytes), *B = aligned_alloc(64, bytes), *C = aligned_alloc(64, bytes);
  for (size_t i = 0; i < (size_t)n * n; i++)
  {
    A[i] = 1.f;
    B[i] = 1.f;
    C[i] = 0.f;
  }
  gemm_blocked(n, A, B, C); // warmup
  double t0 = now();
  gemm_blocked(n, A, B, C);
  double t1 = now();
  double flops = 2.0 * (double)n * n * n;
  printf("n=%d time=%.6f s GFLOP/s=%.2f (MB=%d NB=%d KB=%d)\n",
         n, (t1 - t0), flops / (t1 - t0) / 1e9, MB, NB, KB);
  return 0;
}
#endif