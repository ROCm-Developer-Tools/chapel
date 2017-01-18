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
#include "stringutil.h"
#include "CForLoop.h"
#include "GPUForLoop.h"
#include <iostream>

// Return true if the for loop can be considered for gpu offload ie. if the
// enclosing function or any function in the call-chain for the enclosing fn
// has the flag FLAG_REQUEST_GPU_OFFLOAD set. A way to allow the programmer to
// restrict what loops can be considered for GPU offload. TODO: this shuold
// go away once the code is sufficiently stable.
static bool isGPUOffloadRequested(CForLoop *cForLoop)
{
  FnSymbol *fn = toFnSymbol(cForLoop->parentSymbol);
  while (fn) {
    if (fn->hasFlag(FLAG_REQUEST_GPU_OFFLOAD)) return true;
    FnSymbol* caller = NULL;
    forv_Vec(CallExpr, call, gCallExprs) {
      if (call->inTree()) {
        if (FnSymbol* cfn = call->isResolved()) {
          if (cfn == fn) {
            caller = toFnSymbol(call->parentSymbol);
            break;
          }
        }
      }
    }
    fn = caller;
  }
  return false;
}

// *** Start of mostly copied code ***
// The following few functions are mostly copied from optimizeOnClauses.cpp.
// We should reuse the functions of course, but I am copying this from a
// version in the master branch which is ahead of our current master version.
// Also there are these following minor modifications:
// 1. In setLocal, if a single locale is targeted by the application, we mark
// everything as local.
// 2. We mark some primitives such as PRIM_CHECK_NIL and PRIM_LOCAL_CHECK as
// "NOT FAST" since they can lead to error messages but we are not allowing
// I/O from gpu kernels for now.
// TODO: Once we pull in the changes from the latest master version, consider
// getting rid of the copies.
enum {
  // The primitive is ineligible for a fast (e.g. uses a lock or allocator)
  // AND it causes communication
  NOT_FAST_NOT_LOCAL,
  // Is the primitive ineligible for a fast (e.g. uses a lock or allocator)
  // but communication free?
  LOCAL_NOT_FAST,
  // Does the primitive communicate?
  // This implies NOT_FAST, unless it is in a local block
  // if it is in a local block, this means IS_FAST.
  FAST_NOT_LOCAL,
  // Is the primitive function fast (ie, could it be run in a signal handler)
  // IS_FAST implies IS_LOCAL.
  FAST_AND_LOCAL
};

//
// Return NOT_FAST, NOT_LOCAL, IS_LOCAL, or IS_FAST.
//
static int
classifyPrimitive(CallExpr *call) {
  INT_ASSERT(call->primitive);
  // Check primitives for suitability for executeOnFast and for communication
  switch (call->primitive->tag) {
  case PRIM_UNKNOWN:
    // TODO: Return FAST_AND_LOCAL for PRIM_UNKNOWNs that are side-effect free
    return NOT_FAST_NOT_LOCAL;

  case PRIM_NOOP:
  case PRIM_REF_TO_STRING:
  case PRIM_RETURN:
  case PRIM_UNARY_MINUS:
  case PRIM_UNARY_PLUS:
  case PRIM_UNARY_NOT:
  case PRIM_UNARY_LNOT:
  case PRIM_ADD:
  case PRIM_SUBTRACT:
  case PRIM_MULT:
  case PRIM_DIV:
  case PRIM_MOD:
  case PRIM_LSH:
  case PRIM_RSH:
  case PRIM_EQUAL:
  case PRIM_NOTEQUAL:
  case PRIM_LESSOREQUAL:
  case PRIM_GREATEROREQUAL:
  case PRIM_LESS:
  case PRIM_GREATER:
  case PRIM_AND:
  case PRIM_OR:
  case PRIM_XOR:
  case PRIM_POW:
  case PRIM_MIN:
  case PRIM_MAX:

  case PRIM_GET_MEMBER:
  case PRIM_GET_SVEC_MEMBER:
  case PRIM_GET_PRIV_CLASS:
  case PRIM_NEW_PRIV_CLASS:

  case PRIM_GET_REAL:
  case PRIM_GET_IMAG:

  case PRIM_ADDR_OF:

  case PRIM_INIT_FIELDS:
  case PRIM_PTR_EQUAL:
  case PRIM_PTR_NOTEQUAL:
  case PRIM_CAST:

  case PRIM_BLOCK_LOCAL:

  case PRIM_ON_LOCALE_NUM:
  case PRIM_GET_SERIAL:
  case PRIM_SET_SERIAL:

  case PRIM_START_RMEM_FENCE:
  case PRIM_FINISH_RMEM_FENCE:

  case PRIM_CAST_TO_VOID_STAR:
  case PRIM_SIZEOF:

  case PRIM_GET_USER_LINE:
  case PRIM_GET_USER_FILE:
  case PRIM_LOOKUP_FILENAME:
  case PRIM_FIND_FILENAME_IDX:

  case PRIM_GET_GLOBAL_ID:
    return FAST_AND_LOCAL;

  case PRIM_MOVE:
  case PRIM_ASSIGN:
  case PRIM_ADD_ASSIGN:
  case PRIM_SUBTRACT_ASSIGN:
  case PRIM_MULT_ASSIGN:
  case PRIM_DIV_ASSIGN:
  case PRIM_MOD_ASSIGN:
  case PRIM_LSH_ASSIGN:
  case PRIM_RSH_ASSIGN:
  case PRIM_AND_ASSIGN:
  case PRIM_OR_ASSIGN:
  case PRIM_XOR_ASSIGN:
    if (isCallExpr(call->get(2))) { // callExprs checked in calling function
      // Not necessarily true, but we return true because
      // the callExpr will be checked in the calling function
      return FAST_AND_LOCAL;
    } else {
      bool arg1wide = call->get(1)->typeInfo()->symbol->hasFlag(FLAG_WIDE_REF);
      bool arg2wide = call->get(2)->typeInfo()->symbol->hasFlag(FLAG_WIDE_REF);

      // If neither argument is a wide reference, OK: no communication
      if (!arg1wide && !arg2wide) {
        return FAST_AND_LOCAL;
      }

      if (call->isPrimitive(PRIM_MOVE)) {
        bool arg1ref = call->get(1)->typeInfo()->symbol->hasFlag(FLAG_REF);
        bool arg2ref = call->get(2)->typeInfo()->symbol->hasFlag(FLAG_REF);
        // Handle (move tmp:ref, other_tmp:wide_ref)
        // and    (move tmp:wide_ref, other_tmp:ref)
        // these does not require communication and merely adjust
        // the wideness of the ref.
        if ((arg1wide && arg2ref) || (arg1ref && arg2wide)) {
          return FAST_AND_LOCAL;
        }
      }

      // Otherwise, communication is required if we're not in a local block
      return FAST_NOT_LOCAL;
    }

// I think these can always return true. <hilde>
// But that works only if the remote get is removed from code generation.
  case PRIM_WIDE_GET_LOCALE:
  case PRIM_WIDE_GET_NODE:
  case PRIM_WIDE_GET_ADDR:
    // If this test is true, a remote get is required.
    if (!(call->get(1)->typeInfo()->symbol->hasFlag(FLAG_WIDE_REF) &&
          call->get(1)->getValType()->symbol->hasFlag(FLAG_WIDE_CLASS))) {
      return FAST_AND_LOCAL;
    }
    return FAST_NOT_LOCAL;

  case PRIM_ARRAY_SHIFT_BASE_POINTER:
    // SHIFT_BASE_POINTER is fast as long as none of the
    // arguments are wide references.
    if (call->get(1)->typeInfo()->symbol->hasFlag(FLAG_WIDE_REF) ||
        call->get(2)->typeInfo()->symbol->hasFlag(FLAG_WIDE_REF) ||
        call->get(3)->typeInfo()->symbol->hasFlag(FLAG_WIDE_REF))
      return FAST_NOT_LOCAL;
    else
      return FAST_AND_LOCAL;

  case PRIM_SET_UNION_ID:
  case PRIM_GET_UNION_ID:
  case PRIM_GET_MEMBER_VALUE:
  case PRIM_GET_SVEC_MEMBER_VALUE:
    if (!call->get(1)->typeInfo()->symbol->hasFlag(FLAG_WIDE_REF)) {
      return FAST_AND_LOCAL;
    }
    return FAST_NOT_LOCAL;

  case PRIM_ARRAY_SET:
  case PRIM_ARRAY_SET_FIRST:
  case PRIM_SETCID:
  case PRIM_TESTCID:
  case PRIM_GETCID:
  case PRIM_ARRAY_GET:
  case PRIM_ARRAY_GET_VALUE:
  case PRIM_DYNAMIC_CAST:
    if (!call->get(1)->typeInfo()->symbol->hasFlag(FLAG_WIDE_CLASS)) {
      return FAST_AND_LOCAL;
    }
    return FAST_NOT_LOCAL;

  case PRIM_DEREF:
  case PRIM_SET_MEMBER:
  case PRIM_SET_SVEC_MEMBER:
    if (!call->get(1)->typeInfo()->symbol->hasFlag(FLAG_WIDE_REF) &&
        !call->get(1)->typeInfo()->symbol->hasFlag(FLAG_WIDE_CLASS)) {
      return FAST_AND_LOCAL;
    }
    return FAST_NOT_LOCAL;

  case PRIM_CHPL_COMM_GET:
  case PRIM_CHPL_COMM_PUT:
  case PRIM_CHPL_COMM_ARRAY_GET:
  case PRIM_CHPL_COMM_ARRAY_PUT:
  case PRIM_CHPL_COMM_REMOTE_PREFETCH:
  case PRIM_CHPL_COMM_GET_STRD:
  case PRIM_CHPL_COMM_PUT_STRD:
    // These involve communication
    // MPF: Couldn't these be fast if in a local block?
    // Shouldn't this be return FAST_NOT_LOCAL ?
    return NOT_FAST_NOT_LOCAL;

  case PRIM_SYNC_INIT: // Maybe fast?
  case PRIM_SYNC_DESTROY: // Maybe fast?
  case PRIM_SYNC_LOCK:
  case PRIM_SYNC_UNLOCK:
  case PRIM_SYNC_WAIT_FULL:
  case PRIM_SYNC_WAIT_EMPTY:
  case PRIM_SYNC_SIGNAL_FULL:
  case PRIM_SYNC_SIGNAL_EMPTY:
  case PRIM_SINGLE_INIT: // Maybe fast?
  case PRIM_SINGLE_DESTROY: // Maybe fast?
  case PRIM_SINGLE_LOCK:
  case PRIM_SINGLE_UNLOCK:
  case PRIM_SINGLE_WAIT_FULL:
  case PRIM_SINGLE_SIGNAL_FULL:

  case PRIM_WRITEEF:
  case PRIM_WRITEFF:
  case PRIM_WRITEXF:
  case PRIM_READFE:
  case PRIM_READFF:
  case PRIM_READXX:
  case PRIM_SYNC_IS_FULL:
  case PRIM_SINGLE_WRITEEF:
  case PRIM_SINGLE_READFF:
  case PRIM_SINGLE_READXX:
  case PRIM_SINGLE_IS_FULL:

  case PRIM_IS_GPU_SUBLOCALE: //is there a reason for a gpu-kernel to ask this?
  case PRIM_GPU_REDUCE:
   // These may block, so are deemed slow.
    // However, they are local

  // The following use filename and line numbers as arguments, which we don't
  // want to pass inside a gpu kernel, and these are usually lead to error
  // messages but we are not allowing I/O from gpu kernels for now. So we
  // mark these as "NOT FAST"
  case PRIM_CHECK_NIL:
  case PRIM_LOCAL_CHECK:

   return LOCAL_NOT_FAST;

  case PRIM_NEW:
  case PRIM_INIT:
  case PRIM_NO_INIT:
  case PRIM_TYPE_INIT:
  case PRIM_LOGICAL_FOLDER:
  case PRIM_TYPEOF:
  case PRIM_TYPE_TO_STRING:
  case PRIM_ENUM_MIN_BITS:
  case PRIM_ENUM_IS_SIGNED:
  case PRIM_IS_UNION_TYPE:
  case PRIM_IS_ATOMIC_TYPE:
  case PRIM_IS_SYNC_TYPE:
  case PRIM_IS_SINGLE_TYPE:
  case PRIM_IS_TUPLE_TYPE:
  case PRIM_IS_STAR_TUPLE_TYPE:
  case PRIM_IS_SUBTYPE:
  case PRIM_TUPLE_EXPAND:
  case PRIM_TUPLE_AND_EXPAND:
  case PRIM_QUERY:
  case PRIM_QUERY_PARAM_FIELD:
  case PRIM_QUERY_TYPE_FIELD:
  case PRIM_ERROR:
  case PRIM_WARNING:

  case PRIM_BLOCK_PARAM_LOOP:
  case PRIM_BLOCK_BEGIN:
  case PRIM_BLOCK_COBEGIN:
  case PRIM_BLOCK_COFORALL:
  case PRIM_BLOCK_ON:
  case PRIM_BLOCK_BEGIN_ON:
  case PRIM_BLOCK_COBEGIN_ON:
  case PRIM_BLOCK_COFORALL_ON:
  case PRIM_BLOCK_UNLOCAL:

  case PRIM_ACTUALS_LIST:
  case PRIM_YIELD:

  case PRIM_USE:
  case PRIM_USED_MODULES_LIST:

  case PRIM_WHEN:
  case PRIM_CAPTURE_FN:
  case PRIM_CREATE_FN_TYPE:

  case PRIM_NUM_FIELDS:
  case PRIM_IS_POD:
  case PRIM_FIELD_NUM_TO_NAME:
  case PRIM_FIELD_VALUE_BY_NUM:
  case PRIM_FIELD_ID_BY_NUM:
  case PRIM_FIELD_VALUE_BY_NAME:

  case PRIM_FORALL_LOOP:
  case PRIM_TO_STANDALONE:
  case PRIM_IS_REF_ITER_TYPE:
  case PRIM_COERCE:
  case PRIM_GET_COMPILER_VAR:
  case NUM_KNOWN_PRIMS:
    INT_FATAL("This primitive should have been removed from the tree by now.");
    break;

    // By themselves, loops are considered "fast".
  case PRIM_BLOCK_WHILEDO_LOOP:
  case PRIM_BLOCK_DOWHILE_LOOP:
  case PRIM_BLOCK_FOR_LOOP:
  case PRIM_BLOCK_C_FOR_LOOP:
    return FAST_AND_LOCAL;

    // These don't block in the Chapel sense, but they may require a system
    // call so we don't consider them fast-eligible.
    // However, they are communication free.
    //
  case PRIM_FREE_TASK_LIST:
  case PRIM_ARRAY_ALLOC:
  case PRIM_ARRAY_FREE:
  case PRIM_ARRAY_FREE_ELTS:
  case PRIM_STRING_COPY:
    return LOCAL_NOT_FAST;


    // Temporarily unclassified (legacy) cases.
    // These formerly defaulted to false (slow), so we leave them
    // here until they are proven fast.
  case PRIM_GET_END_COUNT:
  case PRIM_SET_END_COUNT:
  case PRIM_PROCESS_TASK_LIST:
  case PRIM_EXECUTE_TASKS_IN_LIST:
  case PRIM_TO_LEADER:
  case PRIM_TO_FOLLOWER:
  case PRIM_DELETE:
  case PRIM_CALL_DESTRUCTOR:
  case PRIM_HEAP_REGISTER_GLOBAL_VAR:
  case PRIM_HEAP_BROADCAST_GLOBAL_VARS:
  case PRIM_PRIVATE_BROADCAST:
  case PRIM_RT_ERROR:
  case PRIM_RT_WARNING:
  case PRIM_FTABLE_CALL:
  case PRIM_VIRTUAL_METHOD_CALL:
  case PRIM_INT_ERROR:
    return NOT_FAST_NOT_LOCAL;

  // no default, so that it is usually a C compilation
  // error when a primitive is added but not included here.
  }

  // At the end of the switch statement.
  // We get here if there is an unhandled primitive.
  INT_FATAL("Unhandled case.");
  return NOT_FAST_NOT_LOCAL;
}

static int
setLocal(int is, bool inLocal)
{

  // If it's in a local block, it's always local.
  // If a single locale is targeted, it's always local
  if (inLocal|| fLocal) {
    if (is == NOT_FAST_NOT_LOCAL ) is = LOCAL_NOT_FAST;
    if (is == FAST_NOT_LOCAL )     is = FAST_AND_LOCAL;
  }

  return is;
}

static int
classifyPrimitive(CallExpr *call, bool inLocal)
{
  int is = classifyPrimitive(call);

  // If it's in a local block, it's always local.
  is = setLocal(is, inLocal);

  return is;
}

static bool
inLocalBlock(CallExpr *call) {
  for (Expr* parent = call->parentExpr; parent; parent = parent->parentExpr) {
    if (BlockStmt* blk = toBlockStmt(parent)) {
      // NOAKES 2014/11/25  Transitional. Do not trip over blockInfoGet for a Loop
      if (blk->isLoopStmt() == true)
        ;
      else if (blk->blockInfoGet() &&
               blk->blockInfoGet()->isPrimitive(PRIM_BLOCK_LOCAL))
        return true;
    }
  }
  return false;
}
// *** End of copied code ***

// A series of checks to make sure we can generate GPU code for this fn.
// OpenCL does not support recursive functions.
// We only consider primitives / functions which can run in a fast block
// and don't generate communication (local). See optimizeOnClauses.cpp for
// more explanation.
// The optimizeOnClauses pass considers that if CHPL_ATOMICS implementation is
// no locks, the extern functions in the atomics module are local and safe for
// fast on. However, we consider all extern functions to be not fit for GPU
// offload. (TODO: This should not be the case, and we should look at what
// extern functions can be run on the GPU). This is the reason that we donot
// use the FLAG_FAST_ON flag directly.

static bool fitForGPUOffload(FnSymbol * fn, std::set<FnSymbol*>& fnSet)
{
  if (fn->hasFlag(FLAG_FIT_FOR_GPU))
      return true;

  if (fnSet.find(fn) != fnSet.end()) {
    return false;
  }
  if (fn->hasFlag(FLAG_EXTERN) ||
      fn->hasFlag(FLAG_ON_BLOCK) ||
      fn->hasFlag(FLAG_NON_BLOCKING)) {
    return false;
  }

  fnSet.insert(fn);

  std::vector<CallExpr*> calls;
  collectCallExprs(fn, calls);

  for_vector(CallExpr, call, calls) {
    bool inLocal = fn->hasFlag(FLAG_LOCAL_FN) || inLocalBlock(call);

    if (call->primitive) {
      int is = classifyPrimitive(call, inLocal);
      if ((is != FAST_AND_LOCAL)) {
        return false;
      }
    } else {
      FnSymbol* f = call->findFnSymbol();
      if (!fitForGPUOffload(f, fnSet))
        return false;
    }
  }

  fn->addFlag(FLAG_FIT_FOR_GPU);
  return true;
}

static bool isCForLoopFitForGPUOffload(CForLoop *cForLoop)
{
  std::vector<CallExpr*> calls;
  collectCallExprs(cForLoop, calls);
  FnSymbol* fn = toFnSymbol(cForLoop->parentSymbol);
  for_vector(CallExpr, call, calls) {
    bool inLocal  = inLocalBlock(call);
    if (fn)
      inLocal = inLocal || fn->hasFlag(FLAG_LOCAL_FN);

    if (call->primitive) {
      int is = classifyPrimitive(call, inLocal);
      if ((is != FAST_AND_LOCAL)) {
        return false;
      }
    } else {
      std::set<FnSymbol*> fnSet;
      FnSymbol* f = call->findFnSymbol();
      if (!fitForGPUOffload(f, fnSet))
        return false;
    }
  }

  return true;
}
// We can eliminate a variable temp if it is used as follows:
// temp = x;
// temp += y;
// x = temp;
//
// and convert this to:
// x += y;
//
// So we check for:
// 0. The variable is not a ref to some other variable.
// 1. The variable has 2 def expressions - one is assign/move
// and the other is OpEqual. The assign/move source is a symExpr.
// 2. The variable has 2 use expressions - one is assign/move
// and the other is OpEqual. The assign/move target is a symExpr.
// 3. The source and target of the def and use assign/move expressions resp.
// are symExprs with the same symbol.
static bool canEliminate(Symbol* var,
                         Map<Symbol*,Vec<SymExpr*>*>& defMap,
                         Map<Symbol*,Vec<SymExpr*>*>& useMap)
{
  if (var->type->symbol->hasFlag(FLAG_REF)) {
    return false;
  }
  Vec<SymExpr*> *uses = useMap.get(var);
  Vec<SymExpr*> *defs = defMap.get(var);
  if (!defs || defs->n != 2) return false;
  if (!uses || uses->n != 2) return false;
  int numAssign = 0, numOpEqual = 0;
  SymExpr *defRhs = NULL, *useLhs = NULL;
  for_defs(se, defMap, var) {
    CallExpr *call = toCallExpr(se->parentExpr);
    if (call && (call->isPrimitive(PRIM_MOVE) ||
                 call->isPrimitive(PRIM_ASSIGN))) {
      defRhs = toSymExpr(call->get(2));
      if (defRhs)
        numAssign += 1;
    } else if (call && isOpEqualPrim(call)) {
      numOpEqual += 1;
    } else {
      return false;
    }
  }
  if ((numAssign != 1) || (numOpEqual != 1)) return false;
  numAssign = 0, numOpEqual = 0;
  for_uses(se, useMap, var) {
    CallExpr *call = toCallExpr(se->parentExpr);
    if (call && (call->isPrimitive(PRIM_MOVE) ||
                 call->isPrimitive(PRIM_ASSIGN))) {
      useLhs = toSymExpr(call->get(1));
      if (useLhs)
        numAssign += 1;
    } else if (call && isOpEqualPrim(call)) {
      numOpEqual += 1;
    } else {
      return false;
    }
  }
  if ((numAssign != 1) || (numOpEqual != 1)) return false;

  return (defRhs->symbol() == useLhs->symbol());
}

// In some cases, the increment block contains code of the following form:
// temp = x;
// temp += y;
// x = temp;
// where x is the actual index variable.
//
// While estimating trip-count and building index variable scaling
// expressions, we look for code in the form of x += y;
// So we convert the above code to:
// x += y;
//
static void removeTemporaryVariables(BlockStmt *block)
{
  Vec<Symbol*> symSet;
  Vec<SymExpr*> symExprs;
  collectSymbolSetSymExprVec(block, symSet, symExprs);

  Map<Symbol*,Vec<SymExpr*>*> defMap;
  Map<Symbol*,Vec<SymExpr*>*> useMap;
  buildDefUseMaps(symSet, defMap, useMap);

  forv_Vec(Symbol, sym, symSet) {
    if (canEliminate(sym, defMap, useMap)) {
      SymExpr *useLhs = NULL;
      for_uses(se, useMap, sym) {
        CallExpr *call = toCallExpr(se->parentExpr);
        if (call &&
            (call->isPrimitive(PRIM_MOVE) ||
             call->isPrimitive(PRIM_ASSIGN))) {
          useLhs = toSymExpr(call->get(1)->remove());
          call->remove();
        }
      }
      for_defs(se, defMap, sym) {
        CallExpr *call = toCallExpr(se->parentExpr);
        if (call &&
            (call->isPrimitive(PRIM_MOVE) ||
             call->isPrimitive(PRIM_ASSIGN))) {
          call->remove();
        }
        if (call && isOpEqualPrim(call)) {
          SymExpr* lhs = toSymExpr(call->get(1));
          lhs->setSymbol(useLhs->symbol());
        }
      }
      sym->defPoint->remove();
    }
  }
  freeDefUseMaps(defMap, useMap);
}

// Return true if the symbol is defined in an outer function to fn
// third argument not used at call site
static bool isOuterVar(Symbol* sym, FnSymbol* fn, Symbol* parent = NULL)
{
  if (!parent)
    parent = fn->defPoint->parentSymbol;
  if (!isFnSymbol(parent))
    return false;
  else if (sym->defPoint->parentSymbol == parent)
    return true;
  else
    return isOuterVar(sym, fn, parent->defPoint->parentSymbol);
}

// Find variables that are used inside but defined outside the function
static void findOuterVars(FnSymbol* fn, SymbolMap* uses)
{
  std::vector<BaseAST*> asts;
  collect_asts(fn, asts);

  for_vector(BaseAST, ast, asts) {
    if (SymExpr* symExpr = toSymExpr(ast)) {
      Symbol* sym = symExpr->symbol();
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

// 1. For each of the gpu-targeted functions created inside the GPUForLoops,
// capture the external symbols for the function (defined outside and used
// inside) and bundle them into a single function argument. Pass the bundle
// as an argument to the function. Un-bundle into variables inside the
// function body, and replace the external variables with these new varables.
//
// 2. Move function to module level.
//
// For example:
// Original CForLoop:
// var i;
// for (i = k1; i < k2; i += k3) {
//  A[i] = B[i];
// }
//
// New GPUForLoop already built from the CForLoop: (see GPUForLoop.cpp)
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
// GPUForLoop after bundling external variables in this function:
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

static void passExternalSymbols(FnSymbol *fn)
{

  SET_LINENO(fn);
  SymbolMap uses;
  findOuterVars(fn, &uses);

  // create type for the argument bundle
  ModuleSymbol* mod = fn->getModule();
  AggregateType *ctype = createArgBundleClass(uses, mod, fn);

  // add formal arguments
  // 1. Void Pointer to bundled args
  ArgSymbol *bundle_args = new ArgSymbol( INTENT_IN, "bundle", dtCVoidPtr);
  fn->insertFormalAtTail(bundle_args);
  bundle_args->addFlag(FLAG_NO_CODEGEN);

  // 2. Bundled args
  ArgSymbol *wrap_c = new ArgSymbol( INTENT_IN, "dummy_c", ctype);
  fn->insertFormalAtTail(wrap_c);

  // Update values for the symbols in the map with formal arguments
  getNewSymbolsFromFormal(fn, uses, wrap_c, ctype);

  // Replace external symbols with values in the symbol map
  replaceVarUses(fn->body, uses);

  // Update call sites with argument objects
  // There should be only a single caller per gpu-targeted function
  INT_ASSERT(fn->calledBy->n == 1);
  CallExpr *call = fn->calledBy->v[0];
  pruneThisArg(call->parentSymbol, uses); //TODO: is this needed?

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

  // add actual arguments
  // 1. void pointer to bundled args
  call->insertAtTail(allocated_args);
  // 2. bundled args
  call->insertAtTail(tempc);
}

// Move function to module level (denest).
static void flattenFns(FnSymbol *fn)
{
  ModuleSymbol* mod = fn->getModule();
  Expr* def = fn->defPoint;
  def->remove();
  mod->block->insertAtTail(def);
}

// The createGPUForLoops pass considers order-independent CForLoops and
// replaces them with a block of the following form:
//
// var _is_gpu = call_primitive(PRIM_IS_GPU_SUBLOCALE);
// if (_is_gpu) {
//   //...CForLoop block
// } else {
//   // GPUForLoop block
// }
//
// The GPUForLoop block is created from the CForLoop block (GPUForLoop.cpp)
// using a copy of the CForLoop block body.
// The GPUForLoop encapsulates this new block in a function that is later
// offloaded to the GPU. Any symbol external to this function is captured
// and passed as an argument (passExternalSymbols), and the function def
// is moved to module level.

void createGPUForLoops(void)
{
  std::vector<BlockStmt *> blockStmts;
  forv_Vec(BlockStmt, block, gBlockStmts) {
    blockStmts.push_back(block);
  }
  for_vector(BlockStmt, block, blockStmts) {
    if (block->isCForLoop()) {
      CForLoop *cForLoop = toCForLoop(block);
      if (cForLoop->isOrderIndependent() && isGPUOffloadRequested(cForLoop)) {

        // Some checks to make sure we can generate GPU code for this loop
        if (!isCForLoopFitForGPUOffload(cForLoop)) {
          if (fReportGPUForLoops) {
            ModuleSymbol *mod = toModuleSymbol(cForLoop->getModule());
            printf("Failed to generate GPUForLoop from CForLoop at %s:%d\n",
                    mod->name, cForLoop->linenum());
          }
          continue;
        }

        SET_LINENO(block);

        //Remove temporary variables that might be used in the increment block
        removeTemporaryVariables(cForLoop->incrBlockGet());

        GPUForLoop *gpuForLoop = GPUForLoop::buildFromIfPossible(cForLoop);

        if (fReportGPUForLoops) {
          ModuleSymbol *mod = toModuleSymbol(cForLoop->getModule());
          INT_ASSERT(mod);
          if (developer || mod->modTag == MOD_USER) {
            if (gpuForLoop) {
              printf("Replacing CForLoop with C and GPU for loops at %s:%d\n",
                      mod->name, cForLoop->linenum());
            } else {
              printf("Failed to generate GPUForLoop from CForLoop at %s:%d\n",
                      mod->name, cForLoop->linenum());
            }
          }
        }

        if (gpuForLoop) {
          CForLoop *cpuforLoop = cForLoop->copy();
          BlockStmt *condBlock = new BlockStmt();
          VarSymbol* isGpu = newTemp("_is_gpu", dtBool);
          condBlock->insertAtTail(new DefExpr(isGpu));
          condBlock->insertAtTail(new CallExpr(
                PRIM_MOVE, isGpu, new CallExpr(PRIM_IS_GPU_SUBLOCALE)));
          condBlock->insertAtTail(new CondStmt(
                new SymExpr(isGpu), gpuForLoop, cpuforLoop));
          cForLoop->replace(condBlock);
        }
      }
    }
  }

  //Convert external symbols to explicit arguments.
  std::vector<FnSymbol*> gpuFunctions;
  forv_Vec(FnSymbol, fn, gFnSymbols) {
    if (fn->hasFlag(FLAG_OFFLOAD_TO_GPU) && isAlive(fn))
      gpuFunctions.push_back(fn);
  }
  compute_call_sites();
  for_vector(FnSymbol, fn, gpuFunctions) {
    passExternalSymbols(fn);
    flattenFns(fn);
  }
}  // createGPUForLoops()

