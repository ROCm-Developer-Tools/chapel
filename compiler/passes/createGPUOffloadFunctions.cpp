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
#include "passes.h"
#include "scopeResolve.h"
#include "stmt.h"
#include "stlUtil.h"
#include "stringutil.h"

static bool
isOuterVar(Symbol* sym, FnSymbol* fn) {
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

static void
findOuterVars(FnSymbol* fn, SymbolMap& uses) {
  std::vector<BaseAST*> asts;

  collect_asts(fn, asts);

  for_vector(BaseAST, ast, asts) {
    if (SymExpr* symExpr = toSymExpr(ast)) {
      Symbol* sym = symExpr->var;

      if (isLcnSymbol(sym)) {
        if (isOuterVar(sym, fn))
          uses.put(sym, markUnspecified);
      }
    }
  }
}

/*static void
addVarsToFormals(FnSymbol* fn, SymbolMap& vars) {
  form_Map(SymbolMapElem, e, vars) {
      Symbol* sym = e->key;
      if (e->value != markPruned) {
        SET_LINENO(sym);
        IntentTag argTag = INTENT_BLANK;
        if (ArgSymbol* tiMarker = toArgSymbol(e->value))
          argTag = tiMarker->intent;
        else
          INT_ASSERT(e->value == markUnspecified);
        ArgSymbol* arg = new ArgSymbol(argTag, sym->name, sym->type);
        if (ArgSymbol* symArg = toArgSymbol(sym))
          if (symArg->hasFlag(FLAG_MARKED_GENERIC))
            arg->addFlag(FLAG_MARKED_GENERIC);
        fn->insertFormalAtTail(new DefExpr(arg));
        e->value = arg;  // aka vars->put(sym, arg);
      }
  }
}*/

static AggregateType *
createArgBundleClass(SymbolMap& vars, ModuleSymbol *mod, FnSymbol *fn) {
  AggregateType* ctype = new AggregateType(AGGREGATE_CLASS);
  TypeSymbol* new_c = new TypeSymbol(astr("_class_locals", fn->name), ctype);
  new_c->addFlag(FLAG_NO_OBJECT);
  new_c->addFlag(FLAG_NO_WIDE_CLASS);
  int i = 0;
  form_Map(SymbolMapElem, e, vars) {
    Symbol* sym = e->key;
    if (e->value != markPruned) {
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

static void
addNewSymbolsFromFormal(FnSymbol* fn, SymbolMap& vars, ArgSymbol *wrap_c,
  AggregateType *ctype) {
  int i = 1;
  form_Map(SymbolMapElem, e, vars) {
      Symbol* sym = e->key;
      if (e->value != markPruned) {
        SET_LINENO(sym);
        INT_ASSERT(e->value == markUnspecified);
        VarSymbol* tmp = newTemp(sym->name, sym->type);
        fn->insertAtHead(
          new CallExpr(PRIM_MOVE, tmp,
            new CallExpr(PRIM_GET_MEMBER_VALUE, wrap_c, ctype->getField(i))));
        fn->insertAtHead(new DefExpr(tmp));
        e->value = tmp;
      }
  }
}

static void
addVarsToBundle(CallExpr* call, SymbolMap& vars,
                AggregateType *ctype, VarSymbol *tempc) {
  int i = 1;
  form_Map(SymbolMapElem, e, vars) {
    Symbol* sym = e->key;
    if (e->value != markPruned) {
      CallExpr *setc = new CallExpr(PRIM_SET_MEMBER,
          tempc,
          ctype->getField(i),
          sym);
      call->insertBefore(setc);
      i++;
      //call->insertAtTail(sym);
    }
  }
}

/*static void
addVarsToActuals(CallExpr* call, SymbolMap& vars) {
  form_Map(SymbolMapElem, e, vars) {
      Symbol* sym = e->key;
      if (e->value != markPruned) {
        SET_LINENO(sym);
        call->insertAtTail(sym);
      }
  }
}*/

// Create a new pass createGPUOffloadFunctions. This pass converts blocks that
// need to be offloaded to GPUs to separate functions so they can be
// converted to opencl kernels during codegen. (The kernels are then enqueued
// to the GPU for execution). The body of the original block becomes the body
// of the function. The external variables and captured and bundled into a
// single function argument, which are then un-bundled inside the kernel. The
// kernels are added to a kernel vector which is printed out in the form of a
// table during codegen. During execution the hsa runtime intialization code
// uses this table to read and store the finalized kernel code objects.

//
void createGPUOffloadFunctions(void) {
  static int uid = 0;
  // Process coforall blocks that are marked for gpu offloads.
  forv_Vec(BlockStmt, block, gBlockStmts) {
    CallExpr* info = !block->isLoopStmt() ? block->blockInfoGet(): NULL;
    if (info && info->isPrimitive(PRIM_BLOCK_GPU_KERNEL)) {

      SET_LINENO(block);

      ModuleSymbol* mod = block->getModule();
      FnSymbol* fn = new FnSymbol(astr("chpl__gpukernel", istr(uid)));
      fn->addFlag(FLAG_GPU_ON);
      gpuKernelMap[fn] = uid++;
      gpuKernelVec.add(fn);

      block->insertBefore(new DefExpr(fn));

      // Add the call to the outlined task function.
      CallExpr* call = new CallExpr(fn);
      //CallExpr* call = new CallExpr(PRIM_GPU_EXECUTE_KERNEL,
      //                              newCStringSymbol(fn->name));
      block->insertBefore(call);

      block->blockInfoGet()->remove();


      // This block becomes the body of the new function.
      // It is flattened so _downEndCount appears in the same scope as the
      // function formals added below.
      for_alist(stmt, block->body)
        fn->insertAtTail(stmt->remove());

      fn->insertAtTail(new CallExpr(PRIM_RETURN, gVoid));
      fn->retType = dtVoid;

      //Add arguments for workgroup size and workgroup count
      ArgSymbol *wkgrp_count_arg = new ArgSymbol(INTENT_CONST_IN,
                                           "dummy_wkgrpCount_arg",
                                           dtInt[INT_SIZE_64]);
      ArgSymbol *wkgrp_size_arg = new ArgSymbol(INTENT_CONST_IN,
                                           "dummy_wkgrpSizearg",
                                           dtInt[INT_SIZE_64]);
      fn->insertFormalAtTail(wkgrp_count_arg);
      fn->insertFormalAtTail(wkgrp_size_arg);
      wkgrp_count_arg->addFlag(FLAG_NO_CODEGEN);
      wkgrp_size_arg->addFlag(FLAG_NO_CODEGEN);
      Symbol *wkgrp_count = NULL, *wkgrp_size = NULL;
      Expr* parent = fn->defPoint->parentExpr;
      std::vector<BaseAST*> asts;
      collect_asts(parent, asts);
      for_vector(BaseAST, ast, asts) {
        if (SymExpr* symExpr = toSymExpr(ast)) {
          Symbol* sym = symExpr->var;
          if (sym->hasFlag(FLAG_WKGRP_COUNT_VAR)) {
            wkgrp_count = sym;
          }
          if (sym->hasFlag(FLAG_WKGRP_SIZE_VAR)) {
            wkgrp_size = sym;
          }
        }
      }
      INT_ASSERT(wkgrp_count);
      INT_ASSERT(wkgrp_size);
      call->insertAtTail(wkgrp_count);
      call->insertAtTail(wkgrp_size);

      // Convert referenced variables to explicit arguments.
      SymbolMap uses;
      findOuterVars(fn, uses);

      pruneThisArg(call->parentSymbol, uses);

      AggregateType *ctype = createArgBundleClass(uses, mod, fn);

      // create the class variable instance and allocate space for it
      VarSymbol *tempc = newTemp(astr("_args_for", fn->name), ctype);
      call->insertBefore(new DefExpr(tempc));
      /*Symbol *allocTmp = newTemp("chpl_here_alloc_tmp", dtOpaque);
      Symbol* sizeTmp = newTemp("chpl_here_alloc_size", SIZE_TYPE);
      CallExpr *sizeExpr = new CallExpr(PRIM_MOVE, sizeTmp,
                                        new CallExpr(PRIM_SIZEOF,
                                                     new SymExpr(tempc)));
      VarSymbol *mdExpr = newMemDesc(tempc->name);
      CallExpr* allocCall = new CallExpr("chpl_here_alloc", sizeTmp, mdExpr);
      //CallExpr* allocCall = callChplHereAlloc(tempc);
      CallExpr* allocExpr = new CallExpr(PRIM_MOVE, allocTmp, allocCall);
      call->insertBefore(new DefExpr(allocTmp));
      call->insertBefore(new DefExpr(sizeTmp));
      call->insertBefore(sizeExpr);
      call->insertBefore(allocExpr);*/
      insertChplHereAlloc(call, false, tempc,
                          ctype, newMemDesc("bundled args"));

      addVarsToBundle(call, uses, ctype, tempc);
      // Put the bundle into a void* argument
      VarSymbol *allocated_args = newTemp(astr("_args_vfor", fn->name), dtCVoidPtr);
      call->insertBefore(new DefExpr(allocated_args));
      call->insertBefore(new CallExpr(PRIM_MOVE, allocated_args,
                               new CallExpr(PRIM_CAST_TO_VOID_STAR, tempc)));
  	  ArgSymbol *bundle_args = new ArgSymbol( INTENT_IN, "bundle", dtCVoidPtr);
      fn->insertFormalAtTail(bundle_args);
      bundle_args->addFlag(FLAG_NO_CODEGEN);
      ArgSymbol *wrap_c = new ArgSymbol( INTENT_IN, "dummy_c", ctype);
      //wrap_c->addFlag(FLAG_NO_CODEGEN);
      fn->insertFormalAtTail(wrap_c);
      addNewSymbolsFromFormal(fn, uses, wrap_c, ctype);
      //addVarsToActuals(call, uses);
      replaceVarUses(fn->body, uses);
      call->insertAtTail(allocated_args);
      call->insertAtTail(tempc);
    } // if blockInfo
  } // for block

}  // createGPUOffloadFunctions()
