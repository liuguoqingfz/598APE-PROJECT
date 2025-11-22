#include <cblas.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>

static double now(void) {
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

int main(int argc, char** argv) {
    int n = (argc > 1) ? atoi(argv[1]) : 4096;
    const int ld = n;
    const size_t bytes = (size_t)n * n * sizeof(float);

    float *A = (float*)xaligned64(bytes);
    float *B = (float*)xaligned64(bytes);
    float *C = (float*)xaligned64(bytes);

    for (size_t i = 0; i < (size_t)n * n; ++i) {
        A[i] = 1.f;
        B[i] = 1.f;
        C[i] = 0.f;
    }

    const float alpha = 1.f, beta = 0.f;

    for (int w = 0; w < 2; ++w) {
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                    n, n, n, alpha, A, ld, B, ld, beta, C, ld);
    }

    double t0 = now();
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                n, n, n, alpha, A, ld, B, ld, beta, C, ld);
    double t1 = now();

    const double secs  = t1 - t0;
    const double flops = 2.0 * (double)n * n * n;
    const double gflops = flops / secs / 1e9;

    printf("n=%d time=%.6f s GFLOP/s=%.1f\n", n, secs, gflops);

    free(C);
    free(B);
    free(A);
    return 0;
}
