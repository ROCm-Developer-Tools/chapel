/*
 * Copyright 2004-2015 Cray Inc.
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
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

#include "astutil.h"
#include "build.h"
#include "passes.h"
#include "scopeResolve.h"
#include "stmt.h"
#include "stlUtil.h"
#include "CForLoop.h"
#include "GPUForLoop.h"


/* Doesnot work: Recursively inline the fns called by the top-level kernel
static void
InlineCalledFunctions(FnSymbol *fn) {
  std::vector<CallExpr*> calls;
  collectCallExprs(fn, calls);
  collectFnCalls(fn, calls);
  for_vector(CallExpr, call, calls) {
    if (call->parentSymbol) {
      if (FnSymbol *fninner = call->isResolved()) {
        fninner->addFlag(FLAG_INLINE);
        InlineCalledFunctions(fninner);
      }
    }
  }
}
*/

// Create a new pass createGPUForLoops.
// This pass considers order-independent CForLoops and
// 1. replaces them with a block of the following form:
//
// {
//   var _is_gpu = call_primitive(PRIM_IS_GPU_SUBLOCALE);
//   if (_is_gpu) {
//     //...CForLoop block
// } else {
//     // GPUForLoop block
// }
//
// The GPUForLoop block is created from the CForLoop block.

void createGPUForLoops(void) {
  std::vector<BlockStmt *> blockStmts;
  forv_Vec(BlockStmt, block, gBlockStmts) {
    blockStmts.push_back(block);
  }
  for_vector(BlockStmt, block, blockStmts) {
    if (block->isCForLoop()) {
      CForLoop *cForLoop = toCForLoop(block);
      if (cForLoop->isOrderIndependent()) {
        SET_LINENO(block);

        GPUForLoop *gpuforLoop =
          GPUForLoop::buildFrom(cForLoop);;
        CForLoop *cpuforLoop = cForLoop->copy();

        BlockStmt *condBlock = buildChapelStmt();
        VarSymbol* isGpu = newTemp("_is_gpu");
        condBlock->insertAtTail(gpuforLoop);
        condBlock->insertAtTail(cpuforLoop);
        condBlock->insertAtTail(new DefExpr(isGpu));
        condBlock->insertAtTail(new CallExpr(PRIM_MOVE, isGpu,
              new CallExpr(PRIM_IS_GPU_SUBLOCALE)));
        condBlock->insertAtTail(new CondStmt(new SymExpr(isGpu),
              gpuforLoop, cpuforLoop));
        cForLoop->replace(condBlock);
      }
    }
  }
}  // createGPUForLoops()
