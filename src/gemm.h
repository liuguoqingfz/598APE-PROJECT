#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // Your implementations (square n x n; fp32; row-major; beta = 0)
    void gemm_baseline(int n, const float *A, const float *B, float *C);
    void gemm_blocked(int n, const float *A, const float *B, float *C);

#ifdef __cplusplus
}
#endif
