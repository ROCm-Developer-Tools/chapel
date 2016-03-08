
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
load_module_from_file(const char* file_name, char ** buf)
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

    read_size = fread(*buf, sizeof(char), file_size, fp);
    if (read_size != file_size) {
        goto err_free_buffer;
    }

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
    char reduce_kernel_filename[256];
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
    /*printf ("Max work items per workgroup dim: %d\n",
            hsa_device.max_items_per_group_dim);*/
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
    cx = snprintf(reduce_kernel_filename, 256,
                  "%s/runtime/src/chpl-hsa-reducekernels.brig", CHPL_HOME);
    if (cx < 0 || cx  >= 256) {
      OUTPUT_HSA_STATUS(ERROR, Creating reduce kernel filename);
        hsa_queue_destroy(hsa_device.command_queue);
        hsa_shut_down();
        return ERROR;
    }
    /* FIXME: Create all reduction kernels, not just the int32-sum kernel */
    if (ERROR == hsa_create_executable("reduce_int32_sum",
                                       reduce_kernel_filename)) {
      hsa_queue_destroy(hsa_device.command_queue);
      hsa_shut_down();
      return ERROR;
    }

    return SUCCESS;
}

/**
 * Release resources used by the base kernels and tear down the HSA structures
 */
int hsa_shutdown(void)
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

    return err;
}

/**
 * Setup a kernel
 *
 */
int hsa_create_executable(const char * fn_name, const char * file_name)
{
    hsa_status_t st;
    char * kernel_name;
    hsa_executable_symbol_t symbol;
    hsa_ext_module_t module;
    hsa_ext_program_t program;
    hsa_ext_control_directives_t control_directives;
    int size;

    char * module_buffer;
    if (SUCCESS != load_module_from_file(file_name, &module_buffer)) {
        st = HSA_STATUS_ERROR;
        OUTPUT_HSA_STATUS(st, module creation);
        goto err_free_module_buffer;
    }
    module = (hsa_ext_module_t) module_buffer;

    memset(&program, 0, sizeof(hsa_ext_program_t));
    st = hsa_ext_program_create(HSA_MACHINE_MODEL_LARGE,
            HSA_PROFILE_FULL,
            HSA_DEFAULT_FLOAT_ROUNDING_MODE_DEFAULT,
            NULL,
            &program);
    OUTPUT_HSA_STATUS(st, HSA program creation);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_free_module_buffer;
    }

    st = hsa_ext_program_add_module(program, module);
    OUTPUT_HSA_STATUS(st, BRIG module bind to HSA program);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_destroy_program;
    }

    memset(&control_directives, 0, sizeof(hsa_ext_control_directives_t));

    st = hsa_ext_program_finalize(program, hsa_device.isa, 0,
            control_directives, "",
            HSA_CODE_OBJECT_TYPE_PROGRAM,
            &kernel.code_object);
    OUTPUT_HSA_STATUS(st, HSA program finalization);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_destroy_custom_kernel;
    }

    st = hsa_executable_create(HSA_PROFILE_FULL,
            HSA_EXECUTABLE_STATE_UNFROZEN,
            "", &kernel.executable);
    OUTPUT_HSA_STATUS(st, Create the executable);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_destroy_custom_kernel;
    }

    st = hsa_executable_load_code_object(kernel.executable,
            hsa_device.agent,
            kernel.code_object, "");
    OUTPUT_HSA_STATUS(st, Loading the code object);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_destroy_custom_kernel;
    }

    st = hsa_executable_freeze(kernel.executable, "");
    OUTPUT_HSA_STATUS(st, Freeze the executable);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_destroy_custom_kernel;
    }

    size = asprintf(&kernel_name, "&__OpenCL_%s_kernel", fn_name);
    if (-1 == size) {
        goto err_destroy_custom_kernel;
    }

    st = hsa_executable_get_symbol(kernel.executable, NULL,
            kernel_name, hsa_device.agent, 0, &symbol);
    OUTPUT_HSA_STATUS(st, Get symbol handle from executable);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_free_kernel_name;
    }

    kernel.symbol_info = chpl_calloc(1, sizeof(hsa_symbol_info_t));
    if (NULL == kernel.symbol_info) {
        goto err_free_kernel_name;
    }
    st = hsa_executable_symbol_get_info(
            symbol,
            HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_OBJECT,
            &kernel.symbol_info->kernel_object);
    OUTPUT_HSA_STATUS(st, Pull the kernel object handle from symbol);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_free_kernel_name;
    }

    st = hsa_executable_symbol_get_info(
            symbol,
            HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_KERNARG_SEGMENT_SIZE,
            &kernel.symbol_info->kernarg_segment_size);
    OUTPUT_HSA_STATUS(st, Pull the kernarg segment size from executable);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_free_kernel_name;
    }

    st = hsa_executable_symbol_get_info(
            symbol,
            HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_GROUP_SEGMENT_SIZE,
            &kernel.symbol_info->group_segment_size);
    OUTPUT_HSA_STATUS(st, Pull the group segment size from executable);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_free_kernel_name;
    }

    st = hsa_executable_symbol_get_info(
            symbol,
            HSA_EXECUTABLE_SYMBOL_INFO_KERNEL_PRIVATE_SEGMENT_SIZE,
            &kernel.symbol_info->private_segment_size);
    OUTPUT_HSA_STATUS(st, Pull the private segment size from executable);
    if (HSA_STATUS_SUCCESS != st) {
        goto err_free_kernel_name;
    }

    chpl_free(kernel_name);
    hsa_ext_program_destroy(program);
    chpl_free(module_buffer);

    return SUCCESS;

err_free_kernel_name:
    chpl_free(kernel_name);

err_destroy_custom_kernel:
    chpl_free (kernel.symbol_info);
    hsa_executable_destroy(kernel.executable);
    hsa_code_object_destroy(kernel.code_object);

err_destroy_program:
    hsa_ext_program_destroy(program);

err_free_module_buffer:
    chpl_free(module_buffer);

    return ERROR;
}

