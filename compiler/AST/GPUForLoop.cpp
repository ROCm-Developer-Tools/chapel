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
  FnSymbol* fn = new FnSymbol(astr("chpl__gpukernel", istr(func_id)));
  fn->addFlag(FLAG_GPU_ON);
  gpuKernelMap[fn] = func_id;
  gpuKernelVec.add(fn);

  for_alist(expr, cForLoop->body)
    fn->insertAtTail(expr->copy(smap, true));

  fn->insertAtTail(new CallExpr(PRIM_RETURN, gVoid));
  fn->retType = dtVoid;

  return fn;
}

// Create a wkitem-id variable(wkitemId) and initialize with the wkitem
// id obtained from the lower-level GPU wkitem-id function
// for each sym expression found in the loop header init block,
// find all occurrances of the symbol in the function body and replace them
// with the symbol for wkitemId. This only works if the loop indices are
// already in a canonical form.
// FIXME: Handle the general case where a loop index  should be replaced by a
// scaled version of the wkitemId
static void replaceIndexVarUses(GPUForLoop *gpuForLoop, FnSymbol *fn)
{
  //create a variable for the global wkitem id and add it at the top
  VarSymbol* wkitemId = newTemp("_wkitem_id");
  fn->insertAtHead(new CallExpr(PRIM_MOVE, wkitemId,
                                new CallExpr(PRIM_GET_GLOBAL_ID)));
  fn->insertAtHead(new DefExpr(wkitemId));
  for_alist(expr, gpuForLoop->initBlockGet()->body) {
    if (SymExpr* symExpr = toSymExpr(expr)) {
      Symbol* oldSym = symExpr->var;
      SET_LINENO(oldSym);
      std::vector<SymExpr*> symExprs;
      collectSymExprs(fn, symExprs);
      for_vector(SymExpr, se, symExprs)
        if (se->var == oldSym)
          se->var = wkitemId;
    }
  }
}

// Copied from the implementation in createTaskFunctions.cpp
static bool isOuterVar(Symbol* sym, FnSymbol* fn)
{
  Symbol* symParent = sym->defPoint->parentSymbol;
  if (symParent == fn                  || // no need to search
      sym->isParameter()               || // includes isImmediate()
      sym->hasFlag(FLAG_TEMP)          || // exclude these

      // Consts need no special semantics for begin/cobegin/coforall/on.
      // Implementation-wise, it is uniform with consts in nested functions.
      sym->hasFlag(FLAG_CONST)         ||

      // NB 'type' formals do not have INTENT_TYPE
      sym->hasFlag(FLAG_TYPE_VARIABLE)     // 'type' aliases or formals
  ) {
    // these are either not variables or not defined outside of 'fn'
    return false;
  }
  Symbol* parent = fn->defPoint->parentSymbol;
  while (true) {
    if (!isFnSymbol(parent) && !isModuleSymbol(parent))
      return false;
    if (symParent == parent)
      return true;
    if (!parent->defPoint)
      // Only happens when parent==rootModule (right?). This means symParent
      // is not in any of the lexically-enclosing functions/modules, so
      // it's gotta be within 'fn'.
      return false;

    // continue to the enclosing scope
    INT_ASSERT(parent->defPoint->parentSymbol &&
               parent->defPoint->parentSymbol != parent); // ensure termination
    parent = parent->defPoint->parentSymbol;
  }
}

// Find variables that are used inside but defined outside the function
static void findOuterVars(FnSymbol* fn, SymbolMap* uses)
{
  std::vector<BaseAST*> asts;
  collect_asts(fn, asts);

  for_vector(BaseAST, ast, asts) {
    if (SymExpr* symExpr = toSymExpr(ast)) {
      Symbol* sym = symExpr->var;
      if (isLcnSymbol(sym)) {
        if (isOuterVar(sym, fn))
          uses->put(sym, gNil);
      }
    }
  }
}

// Create a class with a field for every externally defined variable in the
// function (following the create_arg_bundle_class() function in parallel.cpp)
static AggregateType *
createArgBundleClass(SymbolMap& vars, ModuleSymbol *mod, FnSymbol *fn)
{
  AggregateType* ctype = new AggregateType(AGGREGATE_CLASS);
  TypeSymbol* new_c = new TypeSymbol(astr("_class_locals", fn->name), ctype);
  new_c->addFlag(FLAG_NO_OBJECT);
  new_c->addFlag(FLAG_NO_WIDE_CLASS);
  int i = 0;
  form_Map(SymbolMapElem, e, vars) {
    Symbol* sym = e->key;
    if (e->value != gVoid) {
      if (sym->type->symbol->hasFlag(FLAG_REF) || isClass(sym->type)) {
      // Only a variable that is passed by reference out of its current scope
      // is concurrently accessed -- which means that it has to be passed by
      // reference.
        sym->addFlag(FLAG_CONCURRENTLY_ACCESSED);
      }
      //call->insertAtTail(sym);
      VarSymbol* field = new VarSymbol(astr("_", istr(i), "_", sym->name),
          sym->type);
      ctype->addDeclarations(new DefExpr(field), true);
      ++i;
    }
  }
  mod->block->insertAtHead(new DefExpr(new_c));
  return ctype;
}

// Set the fields in the bundled argument with the external symbols
static void setBundleFields(CallExpr* call, SymbolMap& vars,
                            AggregateType *ctype, VarSymbol *tempc)
{
  int i = 1;
  form_Map(SymbolMapElem, e, vars) {
    Symbol* sym = e->key;
    if (e->value != gVoid) {
      CallExpr *setc = new CallExpr(PRIM_SET_MEMBER,
          tempc,
          ctype->getField(i),
          sym);
      call->insertBefore(setc);
      i++;
    }
  }
}

// Update values for the symbols in the map with formal arguments
static void getNewSymbolsFromFormal(FnSymbol* fn, SymbolMap& vars,
                                    ArgSymbol *wrap_c,
                                    AggregateType *ctype)
{
  int i = 1;
  form_Map(SymbolMapElem, e, vars) {
      Symbol* sym = e->key;
      if (e->value != gVoid) {
        SET_LINENO(sym);
        INT_ASSERT(e->value == gNil);
        VarSymbol* tmp = newTemp(sym->name, sym->type);
        fn->insertAtHead(
          new CallExpr(PRIM_MOVE, tmp,
            new CallExpr(PRIM_GET_MEMBER_VALUE, wrap_c, ctype->getField(i))));
        fn->insertAtHead(new DefExpr(tmp));
        e->value = tmp;
        ++i;
      }
  }
}

/************************************ | *************************************
*                                                                           *
* Factory method
*                                                                           *
************************************* | ************************************/
// Create the GPUForLoop block from the CForLoop block with the
// following modifications.
//
// Convert the body of the loop to a separate function so it can be later
// codegenned to an opencl kernel. (The kernels are then enqueued to the GPU
// for execution). Assign unique ids to each function and stored the fn-id
// mapping, which is printed out in the form of a table during codegen.
// During execution the hsa runtime intialization code uses this table to read
// and store the finalized kernel code objects.
//
// In the function body:
// Create a wkitem-id variable(wkitemId), which varies from
// [0, num_work_items). wkitemId gets it's value by calling the primitive
// PRIM_GET_GLOBAL_ID, which in turn calls the GPU wkitem-id function.
// Replace all uses of the original loop index variables with a scaled
// version of this work item idi (FIXME: scaling not done yet).
//
// At the call-site:
// Wrkgrp count is hard-coded to 64. TODO: How to set this: 1. User input (
// global / per kernel) 2. Heuristic.
// Code is generated to compute and store the trip-count of the
// loop. trip-count is equal to the number of work items (wkitemCount).
// wkgrpCount and wkitemCount are passed to the function
//
// Capture the external symbols for this function (defined outside and used
// inside) and bundle them into a single function argument. Pass the bundle
// as an argument to the function. Un-bundle into variables inside the
// function body, and replace the external variables with these new varables.
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
// class Bundle {
//  a: A.type;
//  b: B.type;
// };
// Bundle arg_bundle;
// arg_bundle.a = A;
// arg_bundle.b = B
// void *dummy = arg_bundle;
//
// //arg_bundle, wkgrp_size and trip_count are not codegened
// void gpu_func_1 (dummy, arg_bundle, wkgrp_size, trip_count) {
//   var A = dummy.a;
//   var B = dummy.b;
//   var c_idx = call_primitive(GET_GLOBAL_ID);
//   var j = k1 + c_idx * k3;
//   A[j] = B[j];
// }
//
GPUForLoop *GPUForLoop::buildFrom(CForLoop *cForLoop)
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
  FnSymbol *fn = buildGPUOffloadFunction(cForLoop, &smap, uid++);
  retval->insertAtTail(new DefExpr(fn));
  update_symbols(retval, &smap);
  CallExpr* call = new CallExpr(fn);
  retval->insertAtTail(call);

  // Enhancements:
  // replace index varibles with the wkitem id
  replaceIndexVarUses(retval, fn);

  // Convert referenced variables to explicit arguments.
  SymbolMap uses;
  findOuterVars(fn, &uses);
  pruneThisArg(call->parentSymbol, uses); //TODO: is this needed?
  // create type and object for the argument bundle
  ModuleSymbol* mod = cForLoop->getModule();
  AggregateType *ctype = createArgBundleClass(uses, mod, fn);
  VarSymbol *tempc = newTemp(astr("_args_for_", fn->name), ctype);
  call->insertBefore(new DefExpr(tempc));
  insertChplHereAlloc(call, false, tempc, ctype, newMemDesc("bundled args"));
  // initialize the arg-bundle fields using outer varsymbols
  setBundleFields(call, uses, ctype, tempc);
  // Put the bundle into a void* argument
  VarSymbol *allocated_args = newTemp(astr("_args_vfor", fn->name), dtCVoidPtr);
  call->insertBefore(new DefExpr(allocated_args));
  call->insertBefore(new CallExpr(PRIM_MOVE, allocated_args,
                                  new CallExpr(PRIM_CAST_TO_VOID_STAR, tempc)));

  // formal arguments
  // 1.workgroup count
  ArgSymbol *wkgrpCountArg = new ArgSymbol(INTENT_CONST_IN,
                                           "_wkgrp_count_arg",
                                           dtInt[INT_SIZE_64]);
  fn->insertFormalAtTail(wkgrpCountArg);
  wkgrpCountArg->addFlag(FLAG_NO_CODEGEN);
  // 2.workitem count
  ArgSymbol *wkitemCountArg = new ArgSymbol(INTENT_CONST_IN,
                                           "_wkitem_count_arg",
                                           dtInt[INT_SIZE_64]);
  fn->insertFormalAtTail(wkitemCountArg);
  wkitemCountArg->addFlag(FLAG_NO_CODEGEN);
  // 3.Void Pointer to bundled args
  ArgSymbol *bundle_args = new ArgSymbol( INTENT_IN, "bundle", dtCVoidPtr);
  fn->insertFormalAtTail(bundle_args);
  bundle_args->addFlag(FLAG_NO_CODEGEN);
  // 4. Bundled args
  ArgSymbol *wrap_c = new ArgSymbol( INTENT_IN, "dummy_c", ctype);
  fn->insertFormalAtTail(wrap_c);

  // Update values for the symbols in the map with formal arguments
  getNewSymbolsFromFormal(fn, uses, wrap_c, ctype);
  // Replace external symbols with values in the symbol map
  replaceVarUses(fn->body, uses);

  //Vec<FnSymbol*> inlinedSet;
  //inlineCalledFunctions(fn, inlinedSet);

  // actual arguments
  // 1.assign a hardcoded value 64 to workgroup Count
  VarSymbol *wkgrpCount = newTemp("_wkgrp_count", dtInt[INT_SIZE_64]);
  call->insertBefore(new DefExpr(wkgrpCount));
  call->insertBefore(new CallExpr(PRIM_MOVE, new SymExpr(wkgrpCount),
                                    buildIntLiteral("64")));
  call->insertAtTail(wkgrpCount);
  // 2. tripcount / wkitemCount
  // if not possible or tripcount  < 64 return NULL -will retval leak?
  VarSymbol *wkitemCount = newTemp("_wkitem_count", dtInt[INT_SIZE_64]);
  call->insertBefore(new DefExpr(wkitemCount));
  call->insertBefore(new CallExpr(PRIM_MOVE, new SymExpr(wkitemCount),
                                    buildIntLiteral("2048")));
  call->insertAtTail(wkitemCount);
  // 3.void pointer to vundled args
  call->insertAtTail(allocated_args);
  // 4. bundled args
  call->insertAtTail(tempc);

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

  if (outfile) {
    body.codegen("");
  }

  INT_ASSERT(!byrefVars); // these should not persist past parallel()

  return ret;
}

