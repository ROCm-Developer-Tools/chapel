
#include "chpl-atmi.h"
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
 * Estimate and schedule the required number of GPU kernels
 */
    static inline
void atmi_sched_reducekernels(size_t count, 
        void *darray[2], size_t *iter_ct,
        size_t *items_left)
{
    size_t incount, outcount, i, iter, in, out;
    uint32_t max_num_wkgrps, num_wkgroups, grid_size_x;

    const int num_args = 3;
    atmi_task_group_t task_group = {1, ATMI_TRUE};
    ATMI_LPARM(lparm);
    lparm->group = &task_group;
    lparm->kernel_id = REDUCTION_GPU_IMPL;
    lparm->synchronous = ATMI_FALSE;
    lparm->place = (atmi_place_t)ATMI_PLACE_GPU(0, 0);

    incount = count;
    max_num_wkgrps = incount / WKGRP_SIZE;
    num_wkgroups = (max_num_wkgrps + SEQ_CHUNK_SIZE  - 1) / SEQ_CHUNK_SIZE;
    grid_size_x = num_wkgroups * WKGRP_SIZE;
    outcount = num_wkgroups;
    iter = 0;
    while (grid_size_x > WKGRP_SIZE) {
        in = (iter & 1);
        out = (iter & 1) ^ 1;

        void *args[] = {&darray[in], &darray[out], &incount};
        lparm->gridDim[0] = grid_size_x;
        lparm->groupDim[0] = WKGRP_SIZE;
        atmi_task_launch(lparm, reduction_kernel, args);

        iter += 1;
        incount = outcount;
        max_num_wkgrps = incount / WKGRP_SIZE;
        num_wkgroups = (max_num_wkgrps + SEQ_CHUNK_SIZE  - 1) / SEQ_CHUNK_SIZE;
        grid_size_x = num_wkgroups * WKGRP_SIZE;
        outcount = num_wkgroups;
    }

    if (iter > 0) {
        atmi_task_group_sync(&task_group);
    }

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
    darray[0] = src;
    if (0 != chpl_posix_memalign((void **) &darray[1], 64,
                count * sizeof(int64_t))) {
        chpl_exit_any(1);
    }

    atmi_sched_reducekernels(count, (void**)darray,
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
