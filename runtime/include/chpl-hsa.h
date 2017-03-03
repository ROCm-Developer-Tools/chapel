#ifndef _chpl_hsa_h_
#define _chpl_hsa_h_

#include <hsa.h>
#include <hsa_ext_finalize.h>
#include "chpltypes.h"
#include "chpl-hsa-kernelparams.h"

#define HSA_ARGUMENT_ALIGN_BYTES 16
enum ReduceKernel {
 REDUCE_INT64,
 REDUCE_INT32,
 REDUCE_INT16,
 REDUCE_INT8,
 NUM_REDUCE_KERNELS,
};

static inline
const char *reducekernel_name(const enum ReduceKernel kernel_id) {
  static const char *kernel_names[] = {
    "reduce_int64",
    "reduce_int32",
    "reduce_int16",
    "reduce_int8"
  };
  return kernel_names[kernel_id];
}

struct hsa_device_t {
    hsa_agent_t agent;
    hsa_isa_t isa;
    hsa_queue_t *command_queue;
    hsa_region_t kernarg_region;
    uint16_t max_items_per_group_dim;
};
typedef struct hsa_device_t hsa_device_t;
hsa_device_t hsa_device;

struct hsa_symbol_info_t {
    uint64_t kernel_object;
    uint32_t kernarg_segment_size;
    uint32_t group_segment_size;
    uint32_t private_segment_size;
};
typedef struct hsa_symbol_info_t hsa_symbol_info_t;

struct hsa_kernel_t {
    hsa_code_object_t code_object;
    hsa_executable_t executable;
    hsa_symbol_info_t * symbol_info;
};
typedef struct hsa_kernel_t hsa_kernel_t;
hsa_kernel_t reduce_kernels;
hsa_kernel_t gen_kernels;

typedef struct __attribute__ ((aligned(HSA_ARGUMENT_ALIGN_BYTES))) {
#ifndef ROCM
    uint64_t gb0;
    uint64_t gb1;
    uint64_t gb2;
    uint64_t prnt_buff;
    uint64_t vqueue_pntr;
    uint64_t aqlwrap_pntr;
#endif
    uint64_t in;
    uint64_t out;
    uint64_t op;
    uint32_t count;
} hsail_reduce_kernarg_t;

typedef struct __attribute__ ((aligned(HSA_ARGUMENT_ALIGN_BYTES))) {
#ifndef ROCM
    uint64_t gb0;
    uint64_t gb1;
    uint64_t gb2;
    uint64_t prnt_buff;
    uint64_t vqueue_pntr;
    uint64_t aqlwrap_pntr;
#endif
    uint64_t bundle;
} hsail_kernarg_t;

hsa_status_t get_gpu_agent(hsa_agent_t agent, void * data);
hsa_status_t get_kernarg_memory_region(hsa_region_t region, void * data);
int load_module_from_file(const char* file_name, char ** buf, int * size);
int chpl_hsa_initialize(void);
int hsa_shutdown(void);
int hsa_create_reduce_kernels(const char * file_name);
int hsa_create_kernels(const char * file_name);

int64_t hsa_reduce_int64(const char *op, int64_t *src, size_t count);
int32_t hsa_reduce_int32(const char *op, int32_t *src, size_t count);
int16_t hsa_reduce_int16(const char *op, int16_t *src, size_t count);
int8_t hsa_reduce_int8(const char *op, int8_t *src, size_t count);

void hsa_enqueue_kernel(int kernel_idx, uint32_t wkgrp_size_x,
                        uint32_t wkitem_count_x, void *bundled_args);
#endif //_chpl_hsa_h_
