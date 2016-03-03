#pragma OPENCL EXTENSION cl_khr_int64_base_atomics : enable

__kernel void reduce_int64_sum( __global long *in, __global long *out,
                              const size_t count)
{
    size_t tid = get_global_id(0);
    size_t lid = get_local_id(0);
    size_t gid = get_group_id(0);
    volatile __local long temp;
    if (lid == 0) temp = 0;
    barrier(CLK_LOCAL_MEM_FENCE );
    if (tid < count) {
        atom_add(&temp, in[tid]);
    }
    barrier(CLK_LOCAL_MEM_FENCE | CLK_GLOBAL_MEM_FENCE);
    if (lid == 0) {
        out[gid] = temp;
    }
}

__kernel void reduce_int32_sum( __global int *in, __global int *out,
                              const size_t count)
{
    size_t tid = get_global_id(0);
    size_t lid = get_local_id(0);
    size_t gid = get_group_id(0);
    volatile __local int temp;
    if (lid == 0) temp = 0;
    barrier(CLK_LOCAL_MEM_FENCE );
    if (tid < count) {
        atomic_add(&temp, in[tid]);
    }
    barrier(CLK_LOCAL_MEM_FENCE | CLK_GLOBAL_MEM_FENCE);
    if (lid == 0) {
        out[gid] = temp;
    }
}
