#include <cblas.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>

static double now()
{
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec * 1e-9;
}

int main()
{
  int n = 4096;
  size_t bytes = (size_t)n * n * 4;
  float *A = aligned_alloc(64, bytes), *B = aligned_alloc(64, bytes), *C = aligned_alloc(64, bytes);
  for (size_t i = 0; i < (size_t)n * n; i++)
  {
    A[i] = 1.f;
    B[i] = 1.f;
    C[i] = 0.f;
  }
  const float a = 1.f, b = 0.f;
  for (int w = 0; w < 2; ++w)
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, n, n, n, a, A, n, B, n, b, C, n);
  double t0 = now();
  cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, n, n, n, a, A, n, B, n, b, C, n);
  double t1 = now();
  double flops = 2.0 * (double)n * n * n;
  printf("time=%.3fs  GFLOP/s=%.1f\n", t1 - t0, flops / (t1 - t0) / 1e9);
  return 0;
}
