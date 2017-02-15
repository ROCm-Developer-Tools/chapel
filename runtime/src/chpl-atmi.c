
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>
#include <sys/time.h>
#include "chpl-atmi.h"
#include "chplrt.h"
#include "chpl-mem.h"
#include "chplcgfns.h"

#define OUTPUT_ATMI_STATUS(status, msg) \
{ \
    if (ATMI_STATUS_SUCCESS != (status)) { \
        fprintf(stderr, "ATMI support: %s failed, error code: 0x%x\n", \
#msg, status); \
        atmi_finalize(); \
        return status; \
    } \
}

/**
 * Initialize the ATMI/HSA runtime
 */
int chpl_hsa_initialize(void)
{
    char reduce_kernel_filename[1024];
    char gen_kernel_filename[1024];
    int arglen = strlen(chpl_executionCommand)+1;
    char* argCopy = chpl_mem_allocMany(arglen, sizeof(char),
            CHPL_RT_MD_CFG_ARG_COPY_DATA, 0, 0);
    char *binName;
    int cx;

    cx = snprintf(reduce_kernel_filename, 1024,
#ifdef ROCM
            "%s/runtime/src/%s/chpl-hsa-reducekernels.hsaco", CHPL_HOME,
#else
            "%s/runtime/src/%s/chpl-hsa-reducekernels.o", CHPL_HOME,
#endif
            CHPL_RUNTIME_OBJDIR);
    if (cx < 0 || cx  >= 256) {
        OUTPUT_ATMI_STATUS(ATMI_STATUS_ERROR, Creating reduce kernel filename);
    }
    strcpy(argCopy, chpl_executionCommand);
    binName = strtok(argCopy, " ");
#ifdef ROCM
    cx = snprintf(gen_kernel_filename, 1024, "%s_gpu.hsaco", binName);
#else
    cx = snprintf(gen_kernel_filename, 1024, "%s_gpu.o", binName);
#endif
    if (cx < 0 || cx  >= 256) {
        OUTPUT_ATMI_STATUS(ATMI_STATUS_ERROR, Creating generated kernel filename);
    }
    chpl_mem_free(argCopy, 0, 0);

#ifdef ROCM
    atmi_platform_type_t module_type = AMDGCN;
#else
    atmi_platform_type_t module_type = BRIG;
#endif

    /* FIXME: Create all reduction kernels, not just the int64-sum kernel */
    const char *modules[2] = {reduce_kernel_filename, gen_kernel_filename};
    atmi_platform_type_t module_types[2] = {module_type, module_type};
    atmi_status_t st = atmi_module_register(modules, module_types, 2);
    OUTPUT_ATMI_STATUS(st, Registering all modules);

    size_t reduction_arg_sizes[] = {sizeof(uint64_t), sizeof(uint64_t), sizeof(uint32_t)};
    const unsigned int num_reduction_args = sizeof(reduction_arg_sizes)/sizeof(reduction_arg_sizes[0]);
    atmi_kernel_create_empty(&reduction_kernel, num_reduction_args, reduction_arg_sizes);
    atmi_kernel_add_gpu_impl(reduction_kernel, "reduce_int64_sum", REDUCTION_GPU_IMPL);

    size_t kernel_arg_sizes[] = {sizeof(uint64_t)}; 
    const unsigned int num_kernel_args = sizeof(kernel_arg_sizes)/sizeof(kernel_arg_sizes[0]);
    gpu_kernels = (atmi_kernel_t *)chpl_malloc(sizeof(atmi_kernel_t) * chpl_num_gpu_kernels);
    for (int64_t i = 0; i < chpl_num_gpu_kernels; ++i) {
        //FIXME: get the actual kernel name
        const char *kernel_name = chpl_gpu_kernels[i];
        atmi_kernel_create_empty(&gpu_kernels[i], num_kernel_args, kernel_arg_sizes);
        atmi_kernel_add_gpu_impl(gpu_kernels[i], kernel_name, GPU_KERNEL_IMPL);
    }

    return ATMI_STATUS_SUCCESS;
}

/**
 * Release resources used by the base kernels and tear down the HSA structures
 */
int hsa_shutdown(void)
{
    chpl_free(gpu_kernels);
    atmi_finalize();
}
 
/*
 * Enqueue/execute a kernel
 */
void hsa_enqueue_kernel(int kernel_idx, uint32_t wkgrp_size_x,
        uint32_t wkitem_count_x, void *bundled_args)
{
    void *args[] = {&bundled_args}; 
    ATMI_LPARM_1D(lparm, wkitem_count_x);
    lparm->groupDim[0] = wkgrp_size_x;
    lparm->synchronous = ATMI_TRUE;

    lparm->kernel_id = GPU_KERNEL_IMPL;
    lparm->place = (atmi_place_t)ATMI_PLACE_GPU(0, 0);
    atmi_task_launch(lparm, gpu_kernels[kernel_idx], args);
}

