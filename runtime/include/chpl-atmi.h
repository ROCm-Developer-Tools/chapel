#ifndef _chpl_atmi_h_
#define _chpl_atmi_h_

#include <atmi_runtime.h>
#include <stddef.h> /* size_t */
#include <stdint.h> /* uintXX_t */
#ifndef __cplusplus
#include <stdbool.h>
#endif /* __cplusplus */

#include "chpltypes.h"
#include "chpl-hsa-kernelparams.h"

atmi_kernel_t reduction_kernel;
atmi_kernel_t *gpu_kernels;
atmi_kernel_t main_kernel;
int g_num_cpu_kernels;

atmi_machine_t *g_machine;

enum {
    GPU_KERNEL_IMPL = 10565,
    REDUCTION_GPU_IMPL = 42,
    CPU_FUNCTION_IMPL = 43
};    

int chpl_hsa_initialize(void);

int32_t hsa_reduce_int32(const char *op, int32_t *src, size_t count);
int64_t hsa_reduce_int64(const char *op, int64_t *src, size_t count);

void hsa_enqueue_kernel(int kernel_idx, uint32_t wkgrp_size_x,
                        uint32_t wkitem_count_x, void *bundled_args);
#endif //_chpl_atmi_h_
