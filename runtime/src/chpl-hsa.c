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

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>
#include <sys/time.h>
#include "chpl-hsa.h"
#include "chplrt.h"
#include "chpl-mem.h"
#include "chplcgfns.h"

#define OUTPUT_HSA_STATUS(status, msg) \
{ \
    if (HSA_STATUS_SUCCESS != (status)) { \
        fprintf(stderr, "hsa support: %s failed, error code: 0x%x\n", \
#msg, status); \
    } \
}

#define SUCCESS 0
#define ERROR 1

//#define RUNTIME_OBJDIR #CHPL_RUNTIME_OBJDIR
/*
 * Determine if the given agent is of type HSA_DEVICE_TYPE_GPU and sets the
 * value of data to the agent handle if it is.
 */
hsa_status_t
get_gpu_agent(hsa_agent_t agent, void *data)
{
    hsa_status_t status;
    hsa_device_type_t device_type;
    status = hsa_agent_get_info(agent, HSA_AGENT_INFO_DEVICE, &device_type);

    if (HSA_STATUS_SUCCESS == status && HSA_DEVICE_TYPE_GPU == device_type) {
        hsa_agent_t* ret = (hsa_agent_t*)data;
        *ret = agent;
        return HSA_STATUS_INFO_BREAK;
    }

    return HSA_STATUS_SUCCESS;
}

/*
 * Determine if a memory region can be used for kernel argument allocations.
 */
hsa_status_t
get_kernarg_memory_region(hsa_region_t region, void* data)
{
    hsa_region_segment_t segment;
    hsa_region_global_flag_t flags;
    hsa_region_get_info(region, HSA_REGION_INFO_SEGMENT, &segment);
    if (HSA_REGION_SEGMENT_GLOBAL != segment)
        return HSA_STATUS_SUCCESS;

    hsa_region_get_info(region, HSA_REGION_INFO_GLOBAL_FLAGS, &flags);
    if (flags & HSA_REGION_GLOBAL_FLAG_KERNARG) {
        hsa_region_t* ret = (hsa_region_t*) data;
        *ret = region;
        return HSA_STATUS_INFO_BREAK;
    }

    return HSA_STATUS_SUCCESS;
}

/*
 * Load a BRIG module from a specified file. This function does not validate
 * the module.
 */
int
load_module_from_file(const char * file_name, char ** buf, int * buf_size)
{

    FILE *fp = fopen(file_name, "rb");
    size_t read_size, file_size;
    if (NULL == fp) {
        fprintf(stderr, "hsa support: Unable to open file %s\n", file_name);
        return ERROR;
    }

    if (0 != fseek(fp, 0, SEEK_END)) {
        fprintf(stderr, "hsa support: Unable to seek on file %s\n", file_name);
        goto err_close_file;
    }

    file_size = (size_t) (ftell(fp) * sizeof(char));

    if (0 != fseek(fp, 0, SEEK_SET)) {
        fprintf(stderr, "hsa support: Unable to seek on file %s\n", file_name);
        goto err_close_file;
    }

    (*buf) = chpl_malloc(file_size);
    if (NULL == *buf) {
        fprintf(stderr,
                "hsa support: Unable to allocate buffer for brig module\n");
        goto err_close_file;
    }
    memset(*buf, 0, file_size);
    (*buf_size) = file_size;

    read_size = fread(*buf, sizeof(char), file_size, fp);
    if (read_size != file_size) {
        goto err_free_buffer;
    }

    fclose(fp);
    return SUCCESS;

err_free_buffer:
    chpl_free(*buf);

err_close_file:
    fclose(fp);

    return ERROR;
}

/**
 * Initialize the HSA runtime
 *
 * Find an HSA GPU agent
 * Create command queue of max possible size
 * Find suitable memory for kernarg allocation
 * Finalize kernels for pre-defined reductions
 */
int chpl_hsa_initialize(void)
{ 
    uint32_t gpu_max_queue_size;
    char reduce_kernel_filename[1024];
    char gen_kernel_filename[1024];
    int arglen = strlen(chpl_executionCommand)+1;
    char* argCopy = chpl_mem_allocMany(arglen, sizeof(char),
                                     CHPL_RT_MD_CFG_ARG_COPY_DATA, 0, 0);
    char *binName;
    int cx;
    hsa_status_t st = hsa_init();
    OUTPUT_HSA_STATUS(st, HSA initialization);
    if (HSA_STATUS_SUCCESS != st) {
        return ERROR;
    }

    st = hsa_iterate_agents(get_gpu_agent, &hsa_device.agent);
    if (HSA_STATUS_INFO_BREAK == st) {
        st = HSA_STATUS_SUCCESS;
    }
    OUTPUT_HSA_STATUS(st, GPU device search);
    if (HSA_STATUS_SUCCESS != st) {
        hsa_shut_down();
        return ERROR;
    }

    st = hsa_agent_get_info(hsa_device.agent,
            HSA_AGENT_INFO_ISA,
            &hsa_device.isa);
    OUTPUT_HSA_STATUS(st, Query the agents isa);
    if (HSA_STATUS_SUCCESS != st) {
        hsa_shut_down();
        return ERROR;
    }

    st = hsa_agent_get_info(hsa_device.agent,
            HSA_AGENT_INFO_WORKGROUP_MAX_DIM,
            &hsa_device.max_items_per_group_dim);
    OUTPUT_HSA_STATUS(st, GPU max workitem acquisition);

    gpu_max_queue_size = 0;
    st = hsa_agent_get_info(hsa_device.agent,
            HSA_AGENT_INFO_QUEUE_MAX_SIZE,
            &gpu_max_queue_size);
    OUTPUT_HSA_STATUS(st, GPU max queue size acquisition);

    st = hsa_queue_create(hsa_device.agent, gpu_max_queue_size,
            HSA_QUEUE_TYPE_SINGLE, NULL, NULL, UINT32_MAX,
            UINT32_MAX, &hsa_device.command_queue);
    OUTPUT_HSA_STATUS(st, queue creation);
    if (HSA_STATUS_SUCCESS != st) {
        hsa_shut_down();
        return ERROR;
    }

    hsa_device.kernarg_region.handle = (uint64_t)-1;
    hsa_agent_iterate_regions(hsa_device.agent,
            get_kernarg_memory_region,
            &hsa_device.kernarg_region);
    st = ((uint64_t)-1 == hsa_device.kernarg_region.handle) ?
        HSA_STATUS_ERROR : HSA_STATUS_SUCCESS;
    OUTPUT_HSA_STATUS(st, Finding a kernarg memory region);
    if (HSA_STATUS_SUCCESS != st) {
        hsa_queue_destroy(hsa_device.command_queue);
        hsa_shut_down();
        return ERROR;
    }
    cx = snprintf(reduce_kernel_filename, 1024,
#ifdef ROCM
                  "%s/runtime/src/%s/chpl-hsa-reducekernels.hsaco", CHPL_HOME,
#else
                  "%s/runtime/src/%s/chpl-hsa-reducekernels.o", CHPL_HOME,
#endif
                   CHPL_RUNTIME_OBJDIR);
    if (cx < 0 || cx  >= 1023) {
      OUTPUT_HSA_STATUS(ERROR, Creating reduce kernel filename);
        hsa_queue_destroy(hsa_device.command_queue);
        hsa_shut_down();
        return ERROR;
    }
    strcpy(argCopy, chpl_executionCommand);
    binName = strtok(argCopy, " ");
#ifdef ROCM
    cx = snprintf(gen_kernel_filename, 1024, "%s_gpu.hsaco", binName);
#else
    cx = snprintf(gen_kernel_filename, 1024, "%s_gpu.o", binName);
#endif
    chpl_mem_free(argCopy, 0, 0);

    if (cx < 0 || cx  >= 1023) {
      OUTPUT_HSA_STATUS(ERROR, Creating generated kernel filename);
        hsa_queue_destroy(hsa_device.command_queue);
        hsa_shut_down();
        return ERROR;
    }

    if (ERROR == hsa_create_reduce_kernels(reduce_kernel_filename)) {
      hsa_queue_destroy(hsa_device.command_queue);
      hsa_shut_down();
      return ERROR;
    }
    if (ERROR == hsa_create_kernels(gen_kernel_filename)) {
      hsa_queue_destroy(hsa_device.command_queue);
      hsa_shut_down();
      return ERROR;
    }

    return SUCCESS;
}

/**
 * Release resources used by the base kernels and tear down the HSA structures
 */
void hsa_shutdown(void)
{
    int err = SUCCESS;
    hsa_status_t st;

    st = hsa_queue_destroy(hsa_device.command_queue);
    OUTPUT_HSA_STATUS(st, command queue deallocation);
    if (HSA_STATUS_SUCCESS != st) {
        err = ERROR;
    }

    st = hsa_shut_down();
    OUTPUT_HSA_STATUS(st, HSA shutdown);
    if (HSA_STATUS_SUCCESS != st) {
        err = ERROR;
    }
}

/**
 * Setup the generated kernels
 *
 */
int hsa_create_kernels(const char * file_name)
{
    
    hsa_status_t st;
    char * kernel_name;
    hsa_executable_symbol_t symbol;
    int size;

    char * real_suffix = "_real";

    char* pch = strstr(file_name,real_suffix); 
    char origin_exec[256];
    if(pch){
   	strncpy(origin_exec,file_name, strlen(file_name)-strlen(pch));
        strcat(origin_exec,"_gpu.hsaco");
        file_name=origin_exec; 
   }
    char * module_buffer;
    if (SUCCESS != load_module_from_file(file_name, &module_buffer, &size)) {
        st = HSA_STATUS_ERROR;
        OUTPUT_HSA_STATUS(st, module creation);
        goto err_free_module_buffer;
    }

    st = hsa_code_object_deserialize(module_buffer, size, NULL,
                                     &gen_kernels.code_object);
    OUTPUT_HSA_STATUS(st, HSA code object deserialization);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_free_module_buffer;
    }

    st = hsa_executable_create(HSA_PROFILE_FULL,
            HSA_EXECUTABLE_STATE_UNFROZEN,
            "", &gen_kernels.executable);
    OUTPUT_HSA_STATUS(st, Create the executable);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_destroy_gen_kernels;
    }

    st = hsa_executable_load_code_object(gen_kernels.executable,
            hsa_device.agent,
            gen_kernels.code_object, "");
    OUTPUT_HSA_STATUS(st, Loading the code object);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_destroy_gen_kernels;
    }

    st = hsa_executable_freeze(gen_kernels.executable, "");
    OUTPUT_HSA_STATUS(st, Freeze the executable);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_destroy_gen_kernels;
    }
    gen_kernels.symbol_info = chpl_calloc(chpl_num_gpu_kernels,
                                          sizeof(hsa_symbol_info_t));
    if (NULL == gen_kernels.symbol_info) {
        goto err_destroy_gen_kernels;
    }

    for (int64_t i = 0; i < chpl_num_gpu_kernels; ++i) {
      const char * fn_name = chpl_gpu_kernels[i];
#if ROCM
      size = asprintf(&kernel_name, "%s", fn_name);
#else
      size = asprintf(&kernel_name, "&__OpenCL_%s_kernel", fn_name);
#endif
      if (-1 == size) {
        goto err_destroy_gen_kernels;
      }

      st = hsa_executable_get_symbol(gen_kernels.executable, NULL,
        kernel_name, hsa_device.agent, 0, &symbol);
      OUTPUT_HSA_STATUS(st, Get symbol handle from executable);
      if (HSA_STATUS_SUCCESS != st) {
        goto err_free_kernel_name;
      }

      st = hsa_executable_symbol_get_info(
        symbol,
        HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_OBJECT,
        &gen_kernels.symbol_info[i].kernel_object);
      OUTPUT_HSA_STATUS(st, Pull the kernel object handle from symbol);
      if (HSA_STATUS_SUCCESS != st) {
        goto err_free_kernel_name;
      }

      st = hsa_executable_symbol_get_info(
        symbol,
        HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_KERNARG_SEGMENT_SIZE,
        &gen_kernels.symbol_info[i].kernarg_segment_size);
      OUTPUT_HSA_STATUS(st, Pull the kernarg segment size from executable);
      if (HSA_STATUS_SUCCESS != st) {
        goto err_free_kernel_name;
      }

      st = hsa_executable_symbol_get_info(
        symbol,
        HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_GROUP_SEGMENT_SIZE,
        &gen_kernels.symbol_info[i].group_segment_size);
      OUTPUT_HSA_STATUS(st, Pull the group segment size from executable);
      if (HSA_STATUS_SUCCESS != st) {
        goto err_free_kernel_name;
      }

      st = hsa_executable_symbol_get_info(
        symbol,
        HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_PRIVATE_SEGMENT_SIZE,
        &gen_kernels.symbol_info[i].private_segment_size);
      OUTPUT_HSA_STATUS(st, Pull the private segment size from executable);
      if (HSA_STATUS_SUCCESS != st) {
        goto err_free_kernel_name;
      }
    }

    chpl_free(module_buffer);

    return SUCCESS;

err_free_kernel_name:
    chpl_free(kernel_name);

err_destroy_gen_kernels:
    chpl_free (gen_kernels.symbol_info);
    hsa_executable_destroy(gen_kernels.executable);
    hsa_code_object_destroy(gen_kernels.code_object);

err_free_module_buffer:
    chpl_free(module_buffer);

    return ERROR;
}


/**
 * Setup reduce kernels
 *
 */
int hsa_create_reduce_kernels(const char * file_name)
{
    hsa_status_t st;
    char * kernel_name;
    hsa_executable_symbol_t symbol;
    int size;

    char * module_buffer;
    if (SUCCESS != load_module_from_file(file_name, &module_buffer, &size)) {
        st = HSA_STATUS_ERROR;
        OUTPUT_HSA_STATUS(st, module creation);
        goto err_free_module_buffer;
    }

    st = hsa_code_object_deserialize(module_buffer, size, NULL,
                                     &reduce_kernels.code_object);
    OUTPUT_HSA_STATUS(st, HSA code object deserialization);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_free_module_buffer;
    }

    st = hsa_executable_create(HSA_PROFILE_FULL,
            HSA_EXECUTABLE_STATE_UNFROZEN,
            "", &reduce_kernels.executable);
    OUTPUT_HSA_STATUS(st, Create the executable);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_destroy_custom_kernel;
    }

    st = hsa_executable_load_code_object(reduce_kernels.executable,
            hsa_device.agent,
            reduce_kernels.code_object, "");
    OUTPUT_HSA_STATUS(st, Loading the code object);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_destroy_custom_kernel;
    }

    st = hsa_executable_freeze(reduce_kernels.executable, "");
    OUTPUT_HSA_STATUS(st, Freeze the executable reduction);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_destroy_custom_kernel;
    }
    reduce_kernels.symbol_info = chpl_calloc(NUM_REDUCE_KERNELS,
                                     sizeof(hsa_symbol_info_t));
    if (NULL == reduce_kernels.symbol_info) {
        goto err_destroy_custom_kernel;
    }

   for (int i = REDUCE_INT64; i != NUM_REDUCE_KERNELS; ++i) {
      const char *fn_name = reducekernel_name((const enum ReduceKernel)i);
#ifdef ROCM
    	size = asprintf(&kernel_name, "%s", fn_name);
#else
    	size = asprintf(&kernel_name, "&__OpenCL_%s_kernel", fn_name);
#endif 
    	if (-1 == size) {
        	goto err_destroy_custom_kernel;
    	}

    	st = hsa_executable_get_symbol(reduce_kernels.executable, NULL,
            kernel_name, hsa_device.agent, 0, &symbol);
    	OUTPUT_HSA_STATUS(st, Get xxx symbol handle from executable);
    	if (HSA_STATUS_SUCCESS != st) {
        	goto err_free_kernel_name;
    	}

    	st = hsa_executable_symbol_get_info(
            symbol,
            HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_OBJECT,
            &reduce_kernels.symbol_info[i].kernel_object);
    	OUTPUT_HSA_STATUS(st, Pull the kernel object handle from symbol);
    	if (HSA_STATUS_SUCCESS != st) {
        	goto err_free_kernel_name;
    	}

    	st = hsa_executable_symbol_get_info(
            symbol,
            HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_KERNARG_SEGMENT_SIZE,
            &reduce_kernels.symbol_info[i].kernarg_segment_size);
    	OUTPUT_HSA_STATUS(st, Pull the kernarg segment size from executable);
    	if (HSA_STATUS_SUCCESS != st) {
        	goto err_free_kernel_name;
    	}

    	st = hsa_executable_symbol_get_info(
            symbol,
            HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_GROUP_SEGMENT_SIZE,
            &reduce_kernels.symbol_info[i].group_segment_size);
    	OUTPUT_HSA_STATUS(st, Pull the group segment size from executable);
    	if (HSA_STATUS_SUCCESS != st) {
        	goto err_free_kernel_name;
    	}

    	st = hsa_executable_symbol_get_info(
            symbol,
            HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_PRIVATE_SEGMENT_SIZE,
            &reduce_kernels.symbol_info[i].private_segment_size);
    	OUTPUT_HSA_STATUS(st, Pull the private segment size from executable);
    	if (HSA_STATUS_SUCCESS != st) {
        	goto err_free_kernel_name;
    	}
    }	

    chpl_free(module_buffer);

    return SUCCESS;

err_free_kernel_name:
    chpl_free(kernel_name);

err_destroy_custom_kernel:
    chpl_free (reduce_kernels.symbol_info);
    hsa_executable_destroy(reduce_kernels.executable);
    hsa_code_object_destroy(reduce_kernels.code_object);

err_free_module_buffer:
    chpl_free(module_buffer);

    return ERROR;
}

/*
 * Enqueue a kernel
 */
void hsa_enqueue_kernel(int kernel_idx, uint32_t wkgrp_size_x,
                        uint32_t wkitem_count_x, void *bundled_args)
{
  hsa_kernel_dispatch_packet_t * dispatch_packet;
  hsa_queue_t *command_queue = hsa_device.command_queue;
  hsa_symbol_info_t * symbol_info = &gen_kernels.symbol_info[kernel_idx];
  hsa_signal_t completion_signal;
  hsail_kernarg_t *args;
  uint64_t index;
  chpl_msg(2,
           "HSA: Enqueuing a kernel with index %d, wkgrp size %u, "
           "wkitem count %u\n", kernel_idx, wkgrp_size_x, wkitem_count_x);
  hsa_signal_create(1, 0, NULL, &completion_signal);
  hsa_memory_allocate(hsa_device.kernarg_region,
                      symbol_info->kernarg_segment_size,
                      (void**)&args);

  index = hsa_queue_add_write_index_acq_rel(command_queue, 1);
  while (index - hsa_queue_load_read_index_acquire(command_queue) >=
      command_queue->size);
  dispatch_packet =
    (hsa_kernel_dispatch_packet_t*)(command_queue->base_address) +
    (index % command_queue->size);
  memset(dispatch_packet, 0, sizeof(hsa_kernel_dispatch_packet_t));
  dispatch_packet->setup |= 3 <<
    HSA_KERNEL_DISPATCH_PACKET_SETUP_DIMENSIONS;
  dispatch_packet->header |= HSA_FENCE_SCOPE_SYSTEM <<
    HSA_PACKET_HEADER_ACQUIRE_FENCE_SCOPE;
  dispatch_packet->header |= HSA_FENCE_SCOPE_SYSTEM <<
    HSA_PACKET_HEADER_RELEASE_FENCE_SCOPE;
  dispatch_packet->header |= 1 << HSA_PACKET_HEADER_BARRIER;
  dispatch_packet->grid_size_x = wkitem_count_x;
  dispatch_packet->grid_size_y = 1;
  dispatch_packet->grid_size_z = 1;
  dispatch_packet->workgroup_size_x = wkgrp_size_x;
  dispatch_packet->workgroup_size_y = 1;
  dispatch_packet->workgroup_size_z = 1;
  dispatch_packet->private_segment_size = symbol_info->private_segment_size;
  dispatch_packet->group_segment_size = symbol_info->group_segment_size;
  dispatch_packet->kernel_object = symbol_info->kernel_object;

#ifndef ROCM
  args->gb0 = 0;
  args->gb1 = 0;
  args->gb2 = 0;
  args->prnt_buff = 0;
  args->vqueue_pntr = 0;
  args->aqlwrap_pntr = 0;

#endif

  args->bundle = (uint64_t)bundled_args;
  dispatch_packet->kernarg_address = (void*)args;
  dispatch_packet->completion_signal = completion_signal;

  __atomic_store_n((uint8_t*)(&dispatch_packet->header),
      (uint8_t)HSA_PACKET_TYPE_KERNEL_DISPATCH,
      __ATOMIC_RELEASE);


  hsa_signal_store_release(command_queue->doorbell_signal, index);

  while (hsa_signal_wait_acquire(completion_signal, HSA_SIGNAL_CONDITION_LT,
         1, UINT64_MAX, HSA_WAIT_STATE_ACTIVE) > 0);
  hsa_memory_free((void*)args);
  hsa_signal_destroy(completion_signal);
  
  chpl_free (gen_kernels.symbol_info);
  hsa_executable_destroy(gen_kernels.executable);
  hsa_code_object_destroy(gen_kernels.code_object);
}

