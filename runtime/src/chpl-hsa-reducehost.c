
#include "chpl-hsa.h"
#include "chplrt.h"
#include "chplexit.h"
#include "chpl-mem.h"

/*enum ReduceOp {
    MAX,
    MIN,
    SUM,
    PROD,
    BITAND,
    BITOR,
    BITXOR,
    LOGAND,
    LOGOR
  };
*/

/*
 * Enqueue a reduction kernel
 */
static inline
void hsa_enqueue_reducekernel(void *inbuf, void *outbuf, size_t count,
                              uint32_t grid_size_x,
                              hsa_signal_t completion_signal,
                              hsa_symbol_info_t *symbol_info,
                              hsail_reduce_kernarg_t *args)
{
  hsa_kernel_dispatch_packet_t * dispatch_packet;
  hsa_queue_t *command_queue = hsa_device.command_queue;

  uint64_t index = hsa_queue_add_write_index_acq_rel(command_queue, 1);
  chpl_msg(2,
           "HSA: Enqueuing a reduction kernel with sequential chunk size %d, "
           "wkgrp size %d, wkitem size %u, item count %lu\n",
           SEQ_CHUNK_SIZE, WKGRP_SIZE, grid_size_x, count);
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
  dispatch_packet->grid_size_x = grid_size_x;
  dispatch_packet->grid_size_y = 1;
  dispatch_packet->grid_size_z = 1;
  dispatch_packet->workgroup_size_x = WKGRP_SIZE;
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

  args->in = (uint64_t)inbuf;
  args->out = (uint64_t)outbuf;
  args->count = (uint32_t)count;

  dispatch_packet->kernarg_address = (void*)args;
  dispatch_packet->completion_signal = completion_signal;

  __atomic_store_n((uint8_t*)(&dispatch_packet->header),
      (uint8_t)HSA_PACKET_TYPE_KERNEL_DISPATCH,
      __ATOMIC_RELEASE);

  hsa_signal_store_release(command_queue->doorbell_signal, index);
}

/*
 * Estimate and schedule the required number of GPU kernels
 */
static inline
void hsa_sched_reducekernels(size_t count, hsa_symbol_info_t *symbol_info,
                             void *darray[2], size_t *iter_ct,
                             size_t *items_left)
{
  hsail_reduce_kernarg_t **args;
  hsa_signal_t completion_signal;
  size_t incount, outcount, i, iter, in, out;
  uint32_t max_num_wkgrps, num_wkgroups, grid_size_x;

  /*FIXME: This is an overestimation. Allocation count should be equal to the
   * number of iters.
   */
  args = chpl_malloc(count * sizeof (hsail_reduce_kernarg_t*));
  hsa_signal_create(count, 0, NULL, &completion_signal);

  incount = count;
  max_num_wkgrps = incount / WKGRP_SIZE;
  num_wkgroups = (max_num_wkgrps + SEQ_CHUNK_SIZE  - 1) / SEQ_CHUNK_SIZE;
  grid_size_x = num_wkgroups * WKGRP_SIZE;
  outcount = num_wkgroups;
  iter = 0;
  while (grid_size_x > WKGRP_SIZE) {
    in = (iter & 1);
    out = (iter & 1) ^ 1;
    hsa_memory_allocate(hsa_device.kernarg_region,
                        symbol_info->kernarg_segment_size,
                        (void**)&args[iter]);
    hsa_enqueue_reducekernel(darray[in], darray[out], incount,
                             grid_size_x, completion_signal, symbol_info,
                             args[iter]);
    iter += 1;
    incount = outcount;
    max_num_wkgrps = incount / WKGRP_SIZE;
    num_wkgroups = (max_num_wkgrps + SEQ_CHUNK_SIZE  - 1) / SEQ_CHUNK_SIZE;
    grid_size_x = num_wkgroups * WKGRP_SIZE;
    outcount = num_wkgroups;
  }

  if (iter > 0) {
    while (hsa_signal_wait_acquire(completion_signal, HSA_SIGNAL_CONDITION_LT,
          count - iter + 1, UINT64_MAX, HSA_WAIT_STATE_ACTIVE) > count - iter);
  }

  for (i = 0; i <= iter; ++i) {
    hsa_memory_free((void*)args[i]);
  }
  chpl_free (args);
  hsa_signal_destroy(completion_signal);
  (*items_left) = incount;
  (*iter_ct) = iter;
}

/*int32_t hsa_reduce_int32(const char *op, int32_t *src, size_t count)
{
  int32_t res;
  size_t iter, items_left, out, i;
  int32_t * darray[2];
  hsa_symbol_info_t * symbol_info;
  symbol_info = &kernel.symbol_info[0]; //TODO: Remove hardcoded 0 index
  darray[0] = src;
  if (0 != chpl_posix_memalign((void **) &darray[1], 64,
                               count * sizeof(int32_t))) {
    chpl_exit_any(1);
  }

  hsa_sched_reducekernels(count, symbol_info, (void**)darray,
                          &iter, &items_left);

  res = 0;
  out = (iter & 1);
  chpl_msg(2, "HSA: Using CPU to reduce %lu items\n", items_left);
  for (i = 0; i < items_left; ++i) res += darray[out][i];

  chpl_free (darray[1]);
  return res;
}*/

int64_t hsa_reduce_int64(const char *op, int64_t *src, size_t count)
{
  int64_t res;
  size_t iter, items_left, out, i;
  int64_t * darray[2];
  hsa_symbol_info_t * symbol_info;
  symbol_info = &kernel.symbol_info[0]; //TODO: Remove hardcoded 0 index
  darray[0] = src;
  if (0 != chpl_posix_memalign((void **) &darray[1], 64,
                               count * sizeof(int64_t))) {
    chpl_exit_any(1);
  }

  hsa_sched_reducekernels(count, symbol_info, (void**)darray,
                          &iter, &items_left);

  res = 0;
  out = (iter & 1);
  chpl_msg(2, "HSA: Using CPU to reduce %lu items\n", items_left);
  for (i = 0; i < items_left; ++i) res += darray[out][i];

  chpl_free (darray[1]);
  return res;
}

  //FIXME: use the op argument like this to extend this to different ops
  /*if (!strcasecmp(op, "Max"))
    opType = MAX;
    else if (!strcasecmp(op, "Min"))
    opType = MIN;
    else if (!strcasecmp(op, "Sum"))
    opType = SUM;
    else if (!strcasecmp(op, "Product"))
    opType = PROD;
    else if (!strcasecmp(op, "LogicalAnd"))
    opType = LOGAND;
    else if (!strcasecmp(op, "LogicalOr"))
    opType = LOGOR;
    else if (!strcasecmp(op, "BitwiseAnd"))
    opType = BITAND;
    else if (!strcasecmp(op, "BitwiseOr"))
    opType = BITOR;
    else if (!strcasecmp(op, "BitwiseXor"))
    opType = BITXOR; */
