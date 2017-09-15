#include "driver.h"
#include "astutil.h"
#include "build.h"
#include "passes.h"
#include "scopeResolve.h"
#include "stmt.h"
#include "stlUtil.h"
#include "stringutil.h"
#include <iostream>
#include <utility>
extern std::map<FnSymbol *, std::tuple<FnSymbol *, FnSymbol *, AList *, Type *, Type *> > gCustomWellKnownFnMap;

void changeSizeOf(CallExpr *cexpr) {
    if(cexpr) {
        for(int i = 1; i <= cexpr->numActuals(); i++) {
            CallExpr *subExpr = toCallExpr(cexpr->get(i));
            if(subExpr) {
                if(subExpr->resolvedFunction() && !strcmp(subExpr->resolvedFunction()->name, "sizeof")) {
                    
                    SymExpr *arg = toSymExpr(subExpr->get(1));
                    Type *oldType = arg->symbol()->type;
                    AggregateType *tmp_ct = toAggregateType(wideClassMap.get(oldType));
                    Type *arg_ct = (tmp_ct) ? tmp_ct : oldType;
                    VarSymbol *newVar = newTemp("newVar", arg_ct);
                    cexpr->insertBefore(new DefExpr(newVar));
                    subExpr->replace(new CallExpr(PRIM_ABS_SIZEOF, newVar));
                }
                changeSizeOf(subExpr);
            }
        }
    }
}

void createAsyncWrappers(void) {
    ModuleSymbol *mainModule = ModuleSymbol::mainModule();
    SET_LINENO(mainModule);
    for(std::vector<FnSymbol *>::iterator it = gCustomWellKnownFns.begin();
            it != gCustomWellKnownFns.end(); it++) {
        FnSymbol *captured_fn = *it;
        std::tuple<FnSymbol *, FnSymbol*, AList *, Type *, Type *> fn_props = 
            gCustomWellKnownFnMap[captured_fn];

        FnSymbol* asyncWrapperMethod = std::get<0>(fn_props);
        FnSymbol* andThenWrapperMethod = std::get<1>(fn_props);
        AList arg_list = *(std::get<2>(fn_props));
        Type *retType = std::get<3>(fn_props);
        Type *andThenArgType = std::get<4>(fn_props);

        Type *wideRetType = wideClassMap.get(retType);
        AggregateType *ct = toAggregateType(wideRetType);
        if(ct != NULL && isClass(retType)) {
            // now we have to edit all wide class references and widen/narrow them
            // as needed. 
            // Define all temps upfront
            VarSymbol *ptr_ret_class = newTemp("ptr_ret_class", dtCVoidPtr);
            VarSymbol *ret_class = newTemp("ret_class", ct);
            VarSymbol *ptr_x_class = newTemp("ptr_x_class", dtCVoidPtr);

            AggregateType *tmp_ct = toAggregateType(wideClassMap.get(andThenArgType));
            Type *arg_ct = (tmp_ct) ? tmp_ct : andThenArgType;
            VarSymbol *x_class = newTemp("x_class", arg_ct);
            VarSymbol *x_class_addr = newTemp("x_class_addr", andThenArgType);
            
            // for all formals of this wrapper widen those who should be
            // as determined in the preFold pass
            for_formals(arg, asyncWrapperMethod) {
                if(arg->hasFlag(FLAG_MUST_WIDEN)) {
                    if(Type *baseType = arg->type->getValType()) {
                        Type *wideBaseType = wideClassMap.get(baseType);
                        if(wideBaseType && isClass(baseType))
                            arg->type = wideBaseType->refType;
                    }
                }
            }

            // for all def exprs widen those who should be
            // as determined in the preFold pass
            for_alist(expr, asyncWrapperMethod->body->body) {
                if(DefExpr *dexpr = toDefExpr(expr)) {
                    if(VarSymbol *var = toVarSymbol(dexpr->sym))
                        if(var->hasFlag(FLAG_MUST_WIDEN)) {
                            Type *wideVarType = wideClassMap.get(var->type);
                            if(wideVarType && isClass(var->type))
                                var->type = wideVarType;
                        }
                }
            }

            // search through async wrapper, edit return value of wrapped
            // function to wide_class.addr
            for_alist(expr, asyncWrapperMethod->body->body) {
                if(CallExpr *cexpr = toCallExpr(expr)) {
                    if(cexpr->primitive && cexpr->primitive->tag == PRIM_MOVE) {
                        if(CallExpr *rhs = toCallExpr(cexpr->get(2)))
                            if(FnSymbol *fnexpr = rhs->resolvedFunction()) {
                                if(gCustomWellKnownFnMap.find(fnexpr) != gCustomWellKnownFnMap.end()) {
                                    cexpr->insertBefore(new DefExpr(ret_class));
                                    cexpr->get(1)->replace(new SymExpr(ret_class));
                                }
                            }
                    }
                }
            }
            // find memcpy to widen dest ptr
            for_alist_backward(expr, asyncWrapperMethod->body->body) {
                if(CallExpr *cexpr = toCallExpr(expr)) 
                    if(FnSymbol *fnexpr = cexpr->resolvedFunction()) 
                        if(!strcmp(fnexpr->name, "memcpy")) {
                            cexpr->insertBefore(new DefExpr(ptr_ret_class));
                            cexpr->insertBefore(new CallExpr(PRIM_MOVE, ptr_ret_class,
                                        new CallExpr(PRIM_ABS_CAST_TO_VOID_STAR,
                                            new CallExpr(PRIM_ADDR_OF, ret_class))));
                            cexpr->get(2)->replace(new SymExpr(ptr_ret_class));
                            break;
                        }
            }

            // for all formals of this wrapper widen those who should be
            // as determined in the preFold pass
            for_formals(arg, andThenWrapperMethod) {
                if(arg->hasFlag(FLAG_MUST_WIDEN)) {
                    if(Type *baseType = arg->type->getValType()) {
                        Type *wideBaseType = wideClassMap.get(baseType);
                        if(wideBaseType && isClass(baseType))
                            arg->type = wideBaseType->refType;
                    }
                }
            }

            // for all def exprs widen those who should be
            // as determined in the preFold pass
            for_alist(expr, andThenWrapperMethod->body->body) {
                if(DefExpr *dexpr = toDefExpr(expr)) {
                    if(VarSymbol *var = toVarSymbol(dexpr->sym))
                        if(var->hasFlag(FLAG_MUST_WIDEN)) {
                            Type *wideVarType = wideClassMap.get(var->type);
                            if(wideVarType && isClass(var->type))
                                var->type = wideVarType;
                        }
                }
            }

            // search through andThen wrapper
            // find first memcpy (before wrapped fn call) to widen src ptr
            for_alist(expr, andThenWrapperMethod->body->body) {
                if(CallExpr *cexpr = toCallExpr(expr)) 
                    if(FnSymbol *fnexpr = cexpr->resolvedFunction()) 
                        if(!strcmp(fnexpr->name, "memcpy")) {
                            cexpr->get(1)->replace(new SymExpr(ptr_x_class));
                            cexpr->insertAfter(new CallExpr(PRIM_MOVE, x_class_addr, x_class));
                            cexpr->insertBefore(new DefExpr(x_class));
                            cexpr->insertBefore(new DefExpr(ptr_x_class));
                            cexpr->insertBefore(new DefExpr(x_class_addr));
                            cexpr->insertBefore(new CallExpr(PRIM_MOVE, ptr_x_class,
                                        new CallExpr(PRIM_ABS_CAST_TO_VOID_STAR,
                                            new CallExpr(PRIM_ADDR_OF, x_class))));
                            break;
                        }
            }

            // edit return value of wrapped function to wide_class.addr
            for_alist(expr, andThenWrapperMethod->body->body) {
                if(CallExpr *cexpr = toCallExpr(expr)) {
                    if(cexpr->primitive && cexpr->primitive->tag == PRIM_MOVE) {
                        if(CallExpr *rhs = toCallExpr(cexpr->get(2)))
                            if(FnSymbol *fnexpr = rhs->resolvedFunction()) {
                                if(gCustomWellKnownFnMap.find(fnexpr) != gCustomWellKnownFnMap.end()) {
                                    rhs->get(1)->replace(new SymExpr(x_class_addr));
                                    cexpr->insertBefore(new DefExpr(ret_class));
                                    cexpr->get(1)->replace(new SymExpr(ret_class));
                                }
                            }
                    }
                }
            }

            // find last memcpy (after wrapped fn call) to widen dest ptr
            for_alist_backward(expr, andThenWrapperMethod->body->body) {
                if(CallExpr *cexpr = toCallExpr(expr)) 
                    if(FnSymbol *fnexpr = cexpr->resolvedFunction()) 
                        if(!strcmp(fnexpr->name, "memcpy")) {
                            cexpr->insertBefore(new DefExpr(ptr_ret_class));
                            cexpr->insertBefore(new CallExpr(PRIM_MOVE, ptr_ret_class,
                                        new CallExpr(PRIM_ABS_CAST_TO_VOID_STAR,
                                            new CallExpr(PRIM_ADDR_OF, ret_class))));
                            cexpr->get(2)->replace(new SymExpr(ptr_ret_class));
                            break;
                        }
            }
        }

    } 

    forv_Vec(FnSymbol, fn, gFnSymbols) {
        if (fn->hasFlag(FLAG_ASYNC_HELPER_FN) || strstr(fn->name, "getRetSizes")) {
            // find all SIZEOF call expressions, check for widening condition and
            // change PRIM_SIZEOF to PRIM_ABS_SIZEOF
            for_alist(expr, fn->body->body) {
                changeSizeOf(toCallExpr(expr));
            }
        }
    }
}


