#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

    void gemm_baseline(int n, const float *A, const float *B, float *C);
    void gemm_blocked(int n, const float *A, const float *B, float *C);

#ifdef __cplusplus
}
#endif
