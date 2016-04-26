
// We are using the workgroup size as a macro instead of obtaining it at
// runtime using the get_local_size() function since opencl does not support
// dynamic allocation of local-memory arrays, and the hsa runtime doesnot
// support pre-allocation of local memory in the host. hsail does provide a
// way to pass offsets as kernel arguments, and the offsets can be used to 
// access local memory as an offset to the base pointer to the local memory
// segment. But haven't found a way to access the base pointer without using
// hsail assembly directly.

//#pragma OPENCL EXTENSION cl_khr_int64_base_atomics : enable
#include "chpl-hsa-kernelparams.h"

__kernel void reduce_int64_sum( __global long *in, __global long *out,
                              const size_t count)
{
    size_t tid = get_global_id(0);
    size_t lid = get_local_id(0);
    size_t gid = get_group_id(0);
    __local long scratch[WKGRP_SIZE];
    long temp = 0;
    while (tid < count) {
        temp += in[tid];
        tid += get_global_size(0);
    }
    scratch[lid] = temp;
    barrier(CLK_LOCAL_MEM_FENCE );
    for (size_t local_offset = WKGRP_SIZE >> 1;
         local_offset > 0;
         local_offset = local_offset >> 1) {
        if (lid < local_offset) {
            scratch[lid] += scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    if (lid == 0) {
        out[gid] = scratch[0];
    }
}

__kernel void reduce_int32_sum( __global int *in, __global int *out,
                              const size_t count)
{
    size_t tid = get_global_id(0);
    size_t lid = get_local_id(0);
    size_t gid = get_group_id(0);
    __local int scratch[WKGRP_SIZE];
    int temp = 0;
    while (tid < count) {
        temp += in[tid];
        tid += get_global_size(0);
    }
    scratch[lid] = temp;
    barrier(CLK_LOCAL_MEM_FENCE);
    for (size_t local_offset = WKGRP_SIZE >> 1;
         local_offset > 0;
         local_offset = local_offset >> 1) {
        if (lid < local_offset) {
            scratch[lid] += scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    if (lid == 0) {
        out[gid] = scratch[0];
    }
}
