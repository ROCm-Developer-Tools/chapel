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

//==================int64=======================================
//==============================================================
__kernel void reduce_int64( __global long *in, __global long *out,
                            enum ReduceOp op, const size_t count)
{
  size_t tid = get_global_id(0);
  size_t lid = get_local_id(0);
  size_t gid = get_group_id(0);
  __local long scratch[WKGRP_SIZE];
  long temp;
  switch (op) {
    case SUM:
      temp = 0;
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
      break;
    case PROD:
      temp = 1;
      while (tid < count) {
        temp *= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] *= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case LOGICAL_AND:
      temp = 1;
      while (tid < count) {
        temp = temp && in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] = scratch[lid] && scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case LOGICAL_OR:
      temp = 0;
      while (tid < count) {
        temp = temp || in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] = scratch[lid] ||scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case MIN:
      temp = in[tid];
      while (tid < count) {
        temp  = min(temp, in[tid]);
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid]  = min(scratch[lid], scratch[lid + local_offset]);
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case MAX:
      temp = in[tid];
      while (tid < count) {
        temp  = max(temp, in[tid]);
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid]  = max(scratch[lid], scratch[lid + local_offset]);
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_AND:
      temp = -1;
      while (tid < count) {
        temp &= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] &= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_OR:
      temp = 0;
      while (tid < count) {
        temp |= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] |= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_XOR:
      temp = 0;
      while (tid < count) {
        temp ^= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] ^= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    }
    if (lid == 0) {
        out[gid] = scratch[0];
    }
}

//==================int32=======================================
//==============================================================
__kernel void reduce_int32( __global int *in, __global int *out,
                            enum ReduceOp op, const size_t count)
{
  size_t tid = get_global_id(0);
  size_t lid = get_local_id(0);
  size_t gid = get_group_id(0);
  __local int scratch[WKGRP_SIZE];
  int temp;
  switch (op) {
    case SUM:
      temp = 0;
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
      break;
    case PROD:
      temp = 1;
      while (tid < count) {
        temp *= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] *= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case LOGICAL_AND:
      temp = 1;
      while (tid < count) {
        temp = temp && in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] = scratch[lid] && scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case LOGICAL_OR:
      temp = 0;
      while (tid < count) {
        temp = temp || in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] = scratch[lid] ||scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case MIN:
      temp = in[tid];
      while (tid < count) {
        temp  = min(temp, in[tid]);
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid]  = min(scratch[lid], scratch[lid + local_offset]);
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case MAX:
      temp = in[tid];
      while (tid < count) {
        temp  = max(temp, in[tid]);
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid]  = max(scratch[lid], scratch[lid + local_offset]);
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_AND:
      temp = -1;
      while (tid < count) {
        temp &= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] &= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_OR:
      temp = 0;
      while (tid < count) {
        temp |= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] |= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_XOR:
      temp = 0;
      while (tid < count) {
        temp ^= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] ^= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    }
    if (lid == 0) {
        out[gid] = scratch[0];
    }
}

//==================int16=======================================
//==============================================================
__kernel void reduce_int16( __global short *in, __global short *out,
                            enum ReduceOp op, const size_t count)
{
  size_t tid = get_global_id(0);
  size_t lid = get_local_id(0);
  size_t gid = get_group_id(0);
  __local short scratch[WKGRP_SIZE];
  short temp;
  switch (op) {
    case SUM:
      temp = 0;
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
      break;
    case PROD:
      temp = 1;
      while (tid < count) {
        temp *= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] *= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case LOGICAL_AND:
      temp = 1;
      while (tid < count) {
        temp = temp && in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] = scratch[lid] && scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case LOGICAL_OR:
      temp = 0;
      while (tid < count) {
        temp = temp || in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] = scratch[lid] ||scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case MIN:
      temp = in[tid];
      while (tid < count) {
        temp  = min(temp, in[tid]);
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid]  = min(scratch[lid], scratch[lid + local_offset]);
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case MAX:
      temp = in[tid];
      while (tid < count) {
        temp  = max(temp, in[tid]);
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid]  = max(scratch[lid], scratch[lid + local_offset]);
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_AND:
      temp = -1;
      while (tid < count) {
        temp &= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] &= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_OR:
      temp = 0;
      while (tid < count) {
        temp |= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] |= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_XOR:
      temp = 0;
      while (tid < count) {
        temp ^= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] ^= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    }
    if (lid == 0) {
        out[gid] = scratch[0];
    }
}

//==================int8=======================================
//==============================================================
__kernel void reduce_int8( __global char *in, __global char *out,
                            enum ReduceOp op, const size_t count)
{
  size_t tid = get_global_id(0);
  size_t lid = get_local_id(0);
  size_t gid = get_group_id(0);
  __local char scratch[WKGRP_SIZE];
  char temp;
  switch (op) {
    case SUM:
      temp = 0;
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
      break;
    case PROD:
      temp = 1;
      while (tid < count) {
        temp *= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] *= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case LOGICAL_AND:
      temp = 1;
      while (tid < count) {
        temp = temp && in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] = scratch[lid] && scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case LOGICAL_OR:
      temp = 0;
      while (tid < count) {
        temp = temp || in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] = scratch[lid] ||scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case MIN:
      temp = in[tid];
      while (tid < count) {
        temp  = min(temp, in[tid]);
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid]  = min(scratch[lid], scratch[lid + local_offset]);
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case MAX:
      temp = in[tid];
      while (tid < count) {
        temp  = max(temp, in[tid]);
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid]  = max(scratch[lid], scratch[lid + local_offset]);
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_AND:
      temp = -1;
      while (tid < count) {
        temp &= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] &= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_OR:
      temp = 0;
      while (tid < count) {
        temp |= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] |= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    case BIT_XOR:
      temp = 0;
      while (tid < count) {
        temp ^= in[tid];
        tid += get_global_size(0);
      }
      scratch[lid] = temp;
      barrier(CLK_LOCAL_MEM_FENCE );
      for (size_t local_offset = WKGRP_SIZE >> 1;
          local_offset > 0;
          local_offset = local_offset >> 1) {
        if (lid < local_offset) {
          scratch[lid] ^= scratch[lid + local_offset];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
      }
      break;
    }
    if (lid == 0) {
        out[gid] = scratch[0];
    }
}
/*__kernel void reduce_int64_sum( __global long *in, __global long *out,
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
}*/
