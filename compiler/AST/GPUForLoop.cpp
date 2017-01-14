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

#include "GPUForLoop.h"

#include "astutil.h"
#include "AstVisitor.h"
#include "build.h"
#include "codegen.h"
#include "passes.h"
#include "stlUtil.h"
#include "stringutil.h"

typedef std::vector<CallExpr*> CallExprVector;

int GPUForLoop::uid = 0;
/************************************ | *************************************
*                                                                           *
* Helper methods
*                                                                           *
************************************* | ************************************/
// Create a new function with void return type using the body of the cforloop
static FnSymbol *buildGPUOffloadFunction(CForLoop *cForLoop, SymbolMap *smap,
                                         int func_id)
{
  FnSymbol *fn = new FnSymbol(astr("chpl__gpukernel", istr(func_id)));
  fn->addFlag(FLAG_OFFLOAD_TO_GPU);

  for_alist(expr, cForLoop->body)
    fn->insertAtTail(expr->copy(smap, true));

  fn->insertAtTail(new CallExpr(PRIM_RETURN, gVoid));
  fn->retType = dtVoid;

  return fn;
}

// Check if this CForLoop can be converted to a GPU kernel
// Currently we only convert cases where the following constraints hold true:
// 1. The test expression involves testing a single index variable only
// 2. The number of init and incr expressions are equal and there is one each
// of init and incr and exprs working on each index variable.
// 3. The index variable tested in the test call is present in one of
// the init expressions.
// Also collect the expressions in a vector for future processing
// TODO: Handle more than 1 idx variable
static bool checkAndCollectLoopIdxExprs(const GPUForLoop *gpuForLoop,
                                        CallExprVector& initCalls,
                                        CallExprVector& incrCalls,
                                        CallExprVector& testCalls)
{
  int numIndices = 0, numIncrements = 0, numTests = 0;
  for_alist(expr, gpuForLoop->initBlockGet()->body) {
    CallExpr *initCall = toCallExpr(expr);
    if (initCall &&
        (initCall->isPrimitive(PRIM_ASSIGN) ||
        initCall->isPrimitive(PRIM_MOVE))) {
      initCalls.push_back(initCall);
      ++numIndices;
    }
  }

  for_alist(expr, gpuForLoop->incrBlockGet()->body) {
    CallExpr *incrCall = toCallExpr(expr);
    if (incrCall) {
      Symbol *incrSym = toSymExpr(incrCall->get(1))->var;
      for_vector(CallExpr, initCall, initCalls) {
        Symbol *initSym = (toSymExpr(initCall->get(1)))->var;
        if (incrSym == initSym) {
          incrCalls.push_back(incrCall);
          ++numIncrements;
        }
      }
    }
  }
  if ((numIndices == 0) || (numIncrements != numIndices)) return false;

  std::vector<BaseAST*> asts;
  std::set<CallExpr*> callExprSet;
  collect_top_asts(gpuForLoop->testBlockGet(), asts);
  for_vector(BaseAST, ast, asts) {
    CallExpr *testCall = toCallExpr(ast);
    if (testCall && (callExprSet.count(testCall) == 0)) {
      callExprSet.insert(testCall);
      if (testCall->isPrimitive(PRIM_MOVE) ||
          testCall->isPrimitive(PRIM_ASSIGN)) {
        testCall = toCallExpr(testCall->get(2));
        if (!(testCall && (callExprSet.count(testCall) == 0)))
          continue;
        callExprSet.insert(testCall);
      }
      callExprSet.insert(testCall);
      Symbol *testSym = toSymExpr(testCall->get(1))->var;
      bool foundInit = false;
      for_vector(CallExpr, initCall, initCalls) {
        Symbol *initSym = (toSymExpr(initCall->get(1)))->var;
        if (testSym == initSym) {
          foundInit = true;
          testCalls.push_back(testCall);
          ++numTests;
        }
      }
      // There is a test call with no corresponding init call. Not handling
      // this now.
      if(!foundInit) return false;
    }
  }
  if (numTests != 1) return false;

  return true;
}

// Create a wkitem_id variable and initialize with the wkitem
// id obatained from the lower-level GPU function.
// Create a new index variable which is a scaled version of the wkitem_id
// Replace all occurrences of the loop index variable in the function body
// with the new index variable.
// Currently we only consider cases where the increment expressions are
// primitives of the form += or -= and init expressions are primitives of the
// form PRIM_ASSIGN.
// TODO: Handle more  general cases?
static bool replaceIndexVarUsesIfPossible(FnSymbol *fn,
                                          GPUForLoop *gpuForLoop,
                                          const CallExprVector& initCalls)
{
  bool success;
  SymbolMap smap;
  BlockStmt *incrBlock = gpuForLoop->incrBlockGet();
  VarSymbol *wkitemId = newTemp("_wkitem_id", dtUInt[INT_SIZE_64]);
  for_vector(CallExpr, initCall, initCalls) {
    success = false;
    Symbol *oldSym = (toSymExpr(initCall->get(1)))->var;
    SET_LINENO(oldSym);
    VarSymbol *newIndex = newTemp("_new_index", oldSym->type);
    for_alist(expr, incrBlock->body) {
      CallExpr *incrCall = toCallExpr(expr);
      if (incrCall && (toSymExpr(incrCall->get(1))->var == oldSym)) {
        PrimitiveOp* primitiveOp = incrCall->primitive;
        SymExpr *initRhs = new SymExpr(toSymExpr(initCall->get(2))->var);
        SymExpr *incrRhs = new SymExpr(toSymExpr(incrCall->get(2))->var);
        CallExpr *scaleExpr = new CallExpr(PRIM_MULT, incrRhs, wkitemId);
        switch (primitiveOp->tag) {
          case PRIM_ADD_ASSIGN:
            {
              incrCall->replace(new CallExpr(PRIM_MOVE, newIndex, new CallExpr(
                      PRIM_ADD, initRhs, scaleExpr)));
              success = true;
              break;
            }
          case PRIM_SUBTRACT_ASSIGN:
            {
              incrCall->replace(new CallExpr(PRIM_MOVE, newIndex, new CallExpr(
                      PRIM_SUBTRACT, initRhs, scaleExpr)));
              success = true;
              break;
            }
          default:
            break;
        }
      }
    }
    if (!success) break;
    incrBlock->insertAtHead(new DefExpr(newIndex));
    smap.put(oldSym, newIndex);
  }

  if (success) {
    incrBlock->insertAtHead(new CallExpr(PRIM_MOVE, wkitemId,
          new CallExpr(PRIM_GET_GLOBAL_ID)));
    incrBlock->insertAtHead(new DefExpr(wkitemId));
    std::vector<SymExpr*> symExprs;
    collectSymExprs(fn->body, symExprs);
    form_Map(SymbolMapElem, e, smap) {
      Symbol* oldSym = e->key;
      SET_LINENO(oldSym);
      Symbol* newSym = e->value;
      for_vector(SymExpr, se, symExprs)
        if (se->var == oldSym)
          se->var = newSym;
    }
    for_alist_backward(expr, incrBlock->body)
      fn->insertAtHead(expr->remove());
  }
  return success;
}

// Determine wkgrp size and insert as function call arg
// For now, hard-code to 64.(TODO: find a better estimation method)
static void setWkgrpSize(CallExpr *call)
{
  VarSymbol *wkgrpSize = newTemp("_wkgrp_size", dtInt[INT_SIZE_64]);
  call->insertBefore(new DefExpr(wkgrpSize));
  call->insertBefore(new CallExpr(PRIM_MOVE, new SymExpr(wkgrpSize),
                                    buildIntLiteral("64")));
  call->insertAtTail(wkgrpSize);
}

// Try to build an expression to estimate trip count. If possible,
// initialize the wkitem_count function argument with the trip count expr.
// Currently we only consider cases where the test expressions are
// primitives of the form <, <=, >,  >=, and !=.
static bool setWkitemCountIfPossible(CallExpr *call, GPUForLoop *gpuForLoop,
                                     const CallExprVector& initCalls,
                                     const CallExprVector& incrCalls,
                                     const CallExprVector& testCalls)
{
  bool success;
  //BlockStmt *incrBlock = gpuForLoop->incrBlockGet();
  for_vector(CallExpr, testCall, testCalls) {
    success = false;
    Symbol *testSym = toSymExpr(testCall->get(1))->var;
    SymExpr *testRhs = new SymExpr(toSymExpr(testCall->get(2))->var);
    PrimitiveOp* primitiveTestOp = testCall->primitive;
    if (!primitiveTestOp) continue;
    for_vector(CallExpr, incrCall, incrCalls) {
      Symbol *incrSym = toSymExpr(incrCall->get(1))->var;
      if (testSym == incrSym) {
        SymExpr *incrRhs = new SymExpr(toSymExpr(incrCall->get(2))->var);
        for_vector(CallExpr, initCall, initCalls) {
          Symbol *initSym = (toSymExpr(initCall->get(1)))->var;
          if (testSym == initSym) {
            SymExpr *initRhs = new SymExpr(toSymExpr(initCall->get(2))->var);
            CallExpr *diffExpr;
            switch (primitiveTestOp->tag) {
              case PRIM_LESSOREQUAL:
                {
                  diffExpr = new CallExpr(PRIM_ADD,
                      buildIntLiteral("1"), new CallExpr(
                        PRIM_SUBTRACT, testRhs, initRhs));
                  success = true;
                  break;
                }
              case PRIM_LESS:
                {
                  diffExpr = new CallExpr(PRIM_SUBTRACT, testRhs, initRhs);
                  success = true;
                  break;
                }
              case PRIM_GREATEROREQUAL:
                {
                  diffExpr = new CallExpr(PRIM_ADD, buildIntLiteral("1"),
                      new CallExpr(PRIM_SUBTRACT,
                        initRhs, testRhs));
                  success = true;
                  break;
                }
              case PRIM_GREATER:
                {
                  diffExpr = new CallExpr(PRIM_SUBTRACT, initRhs, testRhs);
                  success = true;
                  break;
                }
              case PRIM_NOTEQUAL:
                {
                  PrimitiveOp* primitiveIncrOp = incrCall->primitive;
                  if (primitiveIncrOp->tag == PRIM_ADD_ASSIGN) {
                    diffExpr = new CallExpr(PRIM_SUBTRACT, testRhs, initRhs);
                    success = true;
                  } else if (primitiveIncrOp->tag == PRIM_SUBTRACT_ASSIGN) {
                    diffExpr = new CallExpr(PRIM_SUBTRACT, initRhs, testRhs);
                    success = true;
                  } else {
                    ;
                  }
                  break;
                }
              default:
                break;
            }
            if (!success) break;
            VarSymbol *wkitemCount = newTemp("_wkitem_count",
                dtInt[INT_SIZE_64]);
            CallExpr *qtExpr = new CallExpr(PRIM_DIV, diffExpr, incrRhs);
            CallExpr *remExpr = new CallExpr(
                PRIM_NOTEQUAL, buildIntLiteral("0"), new CallExpr(
                  PRIM_MOD, diffExpr->copy(), incrRhs->copy()));
            CallExpr *sumExpr = new CallExpr(PRIM_ADD, qtExpr, remExpr);
            CallExpr *setWkitemCount = new CallExpr(
                PRIM_MOVE, wkitemCount, sumExpr);
            call->insertBefore(new DefExpr(wkitemCount));
            call->insertBefore(setWkitemCount);
            call->insertAtTail(wkitemCount);
          }
        }
      }
    }
  }
  return success;
}

/************************************ | *************************************
*                                                                           *
* Factory methods
*                                                                           *
************************************* | ************************************/
// Create the GPUForLoop block from the CForLoop block with the
// following modifications.
//
// Convert the body of the loop to a separate function so it can be later
// codegenned to an opencl kernel. (The kernels are then enqueued to the GPU
// for execution). Assign unique ids to each function and store the fn-id
// mapping, which is printed out in the form of a table during codegen.
// During execution, the hsa runtime intialization code uses this table to
// read and store the finalized kernel code objects.
//
// In the function body:
// Create a wkitem-id variable(wkitemId), which varies from
// [0, num_work_items). wkitemId gets it's value by calling the primitive
// PRIM_GET_GLOBAL_ID, which in turn calls the GPU wkitem-id function.
// Replace all uses of the original loop index variables with a scaled
// version of this work item id.
//
// At the call-site:
// Determine wrkgrp size -- currently hard-coded to 64.
// TODO: How to set this: 1. User input (global / per kernel) 2. Heuristic.
// Determine workitem count - Generate code to compute and store the
// trip-count (equal to the number of work items ie. wkitemCount).
// Pass wkgrpSize and wkitemCount to the function.
//
// For example:
//
// CForLoop:
// var i;
// for (i = k1; i < k2; i += k3) {
//  A[i] = B[i];
// }
//
// GPUForLoop:
// var i;
// var trip_count = (k2 - k1) / k3 + ((k2 - k1) % k3 != 0);
//
// //arg_bundle, wkgrp_size and trip_count are not codegened
// void gpu_func_1 (wkgrp_size, trip_count) {
//   var c_idx = call_primitive(GET_GLOBAL_ID);
//   var j = k1 + c_idx * k3;
//   A[j] = B[j];
// }
//
GPUForLoop *GPUForLoop::buildFromIfPossible(CForLoop *cForLoop)
{
  SymbolMap smap;
  GPUForLoop *retval = new GPUForLoop();

  retval->astloc            = cForLoop->astloc;
  retval->blockTag          = cForLoop->blockTag;
  retval->mBreakLabel       = cForLoop->breakLabelGet();
  retval->mContinueLabel    = cForLoop->continueLabelGet();
  retval->mOrderIndependent = cForLoop->isOrderIndependent();
  if (cForLoop->initBlockGet() != 0 &&
      cForLoop->testBlockGet() != 0 &&
      cForLoop->incrBlockGet() != 0) {
    retval->loopHeaderSet(cForLoop->initBlockGet()->copy(&smap, true),
                          cForLoop->testBlockGet()->copy(&smap, true),
                          cForLoop->incrBlockGet()->copy(&smap, true));

  } else {
    INT_ASSERT(false);
  }

  // Define and call the function that will be executed on a GPU.
  FnSymbol *fn = buildGPUOffloadFunction(cForLoop, &smap, uid);
  retval->insertAtTail(new DefExpr(fn));
  update_symbols(retval, &smap);
  CallExpr* call = new CallExpr(fn);
  retval->insertAtTail(call);

  // Enhancements:
  CallExprVector initCalls;
  CallExprVector incrCalls;
  CallExprVector testCalls;
  // Check if the CForLoop can be converted to a GPU kernel
  if (!checkAndCollectLoopIdxExprs(retval, initCalls, incrCalls, testCalls))
    return NULL;

  // Add gpu execution params as actual arguments
  // 1. wkgrp size
  setWkgrpSize(call);
  // 2. tripcount / wkitemCount
  if (!setWkitemCountIfPossible(call, retval, initCalls, incrCalls, testCalls))
    return NULL;

  // Try to replace index variable with a new variable obtained from the GPU
  // workitem id.
  if (!replaceIndexVarUsesIfPossible(fn, retval, initCalls))
    return NULL;
  // gpu execution parameters as dummy formal arguments
  // 1.workgroup count
  ArgSymbol *wkgrpSizeArg = new ArgSymbol(INTENT_CONST_IN,
                                           "_wkgrp_size_arg",
                                           dtInt[INT_SIZE_64]);
  fn->insertFormalAtTail(wkgrpSizeArg);
  wkgrpSizeArg->addFlag(FLAG_NO_CODEGEN);
  // 2.workitem count
  ArgSymbol *wkitemCountArg = new ArgSymbol(INTENT_CONST_IN,
                                           "_wkitem_count_arg",
                                           dtInt[INT_SIZE_64]);
  fn->insertFormalAtTail(wkitemCountArg);
  wkitemCountArg->addFlag(FLAG_NO_CODEGEN);

  // Successfully created gpu kernel. Hence update the kernel table.
  gpuKernelMap[fn] = uid++;
  gpuKernelVec.push_back(fn);

  return retval;
}

/************************************ | *************************************
*                                                                           *
* Instance methods                                                          *
*                                                                           *
************************************* | ************************************/

GPUForLoop::GPUForLoop() : CForLoop()
{

}

GPUForLoop::~GPUForLoop()
{

}

GPUForLoop *GPUForLoop::copy(SymbolMap* mapRef, bool internal)
{
  SymbolMap  localMap;
  SymbolMap* map       = (mapRef != 0) ? mapRef : &localMap;
  GPUForLoop*  retval    = new GPUForLoop();

  retval->astloc            = astloc;
  retval->blockTag          = blockTag;

  retval->mBreakLabel       = mBreakLabel;
  retval->mContinueLabel    = mContinueLabel;
  retval->mOrderIndependent = mOrderIndependent;

  if (initBlockGet() != 0 && testBlockGet() != 0 && incrBlockGet() != 0)
    retval->loopHeaderSet(initBlockGet()->copy(map, true),
                          testBlockGet()->copy(map, true),
                          incrBlockGet()->copy(map, true));

  else if (initBlockGet() != 0 && testBlockGet() != 0 && incrBlockGet() != 0)
    INT_ASSERT(false);

  for_alist(expr, body)
    retval->insertAtTail(expr->copy(map, true));

  if (internal == false)
    update_symbols(retval, map);

  return retval;
}

GenRet GPUForLoop::codegen()
{
  GenInfo* info    = gGenInfo;
  FILE*    outfile = info->cfile;
  GenRet   ret;

  codegenStmt(this);
  if (this != getFunction()->body)
    info->cStatements.push_back("{\n");

  if (outfile) {
    body.codegen("");
  }

  if (this != getFunction()->body)
    info->cStatements.push_back("}\n");

  return ret;
}

