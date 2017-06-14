/*
 * Copyright 2017 Advanced Micro Devices, Inc.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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
