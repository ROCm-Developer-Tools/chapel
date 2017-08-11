/*
 * Copyright 2004-2017 Cray Inc.
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

/*

.. |---| unicode:: U+2014

Containers for accessing the results of asynchronous execution.

A :record:`Future` object is a container that can store the result of an
asynchronous operation, which can be retrieved when the result is ready.

Usage
-----

A valid :record:`Future` object is not created directly. Instead, a future may
be created by calling the :proc:`async()` function, which takes as arguments
the function to be executed and all arguments to that function.

The following example demonstrates a trivial use of futures. Three computations
are executed asynchronously.

.. literalinclude:: ../../../../test/modules/packages/Futures/futures-doc-simple.chpl
   :language: chapel

.. _valid-futures:

Validity of Futures
-------------------

A future that is initialized by a call to :proc:`async()` or
:proc:`Future.andThen()` is created in a valid state.  Otherwise |---| for
example, when a future is declared but not initialized |---| the future is in
an invalid state and method calls other than :proc:`Future.isValid()` on an
invalid future will :proc:`~ChapelIO.halt()`.  If such a future object is subsequently
assigned to by a call to :proc:`async()` or :proc:`Future.andThen()`, then
the future will become valid.

.. literalinclude:: ../../../../test/modules/packages/Futures/futures-doc-validity.chpl
   :language: chapel

Task Arguments
--------------

The task argument in a call to :proc:`async()` or :proc:`Future.andThen()`
may be a :ref:`first-class function <readme-firstClassFns>`, a
:ref:`lambda function <readme-lambdaFns>`, or a specially-constructed
class or record.  Such a record must have both a `proc this()` method for the
desired computation and a `proc retType type` method that returns the return
type of the `this()` method.  (The requirement for the `retType` method is
a currently limitation that is intended to be resolved in the future.)
For example:

.. literalinclude:: ../../../../test/modules/packages/Futures/futures-doc-taskfn.chpl
   :language: chapel

Future Chaining
---------------

A continuation to a future (itself a future) can be created via the
:proc:`Future.andThen()` method, which takes as its single argument a function
to be invoked asynchronously (with respect to other tasks) but strictly ordered
in execution after the result of the parent future is ready. The continuation
function takes a single argument, the result of the parent future.

The following examples demonstrate such chaining of futures.

.. literalinclude:: ../../../../test/modules/packages/Futures/futures-doc-chaining1.chpl
   :language: chapel

.. literalinclude:: ../../../../test/modules/packages/Futures/futures-doc-chaining2.chpl
   :language: chapel

Future Bundling
---------------

A set of futures can be bundled via :proc:`Future.waitAll()`, which takes a
variable number of futures as arguments and returns a new future whose return
type is a tuple of the return types of the arguments.  The returned future is
ready only when all the future arguments are ready.

The following example demonstrate bundling of futures.

.. literalinclude:: ../../../../test/modules/packages/Futures/futures-doc-waitall.chpl
   :language: chapel

 */

module Futures {
  extern proc chpl_taskLaunch(fn: c_fn_ptr, n: c_uint, args_sizes: [] uint(64),
              args: c_void_ptr, dep_tasks: [] uint(64), dep_tasks_n: uint(64)) : uint(64);
  extern proc chpl_gpuTaskLaunch(kernelName: c_string,
              n: c_uint, args_sizes: [] uint(64),
              args: c_void_ptr, dep_tasks: [] uint(64), dep_tasks_n: uint(64)) : uint(64);
  extern proc chpl_taskWaitFor(handle: uint(64));
  extern proc memcpy (dest: c_void_ptr, const src: c_void_ptr, n: size_t);

  use Reflection;
  use ExplicitRefCount;

  var gpuFiles: domain(string);

  pragma "no doc"
  class FutureClass: RefCountBase {

    type retType;

    var valid: bool = false;
    var value: retType;
    var state: atomic bool;
    var handle: uint(64);

    proc FutureClass(type retType) {
      refcnt.write(0);
      state.clear();
      handle = 0;
    }

  } // class FutureClass

  /*
    A container that can store the result of an asynchronous operation,
    which can be retrieved when the result is ready.

    A future is not created directly. Instead, one is created by calling the
    :proc:`async()` function or the :proc:`Future.andThen()` method on
    an already-existing future.
   */
  record Future {

    /*
      The return type of the future.
     */
    type retType;

    pragma "no doc"
    var classRef: FutureClass(retType) = nil;

    pragma "no doc"
    proc Future(type retType) {
      acquire(new FutureClass(retType));
    }

    pragma "no doc"
    proc deinit() {
      release();
    }

    /*
      Get the result of a future, blocking until it is available.

      If the future is not valid, this call will :proc:`~ChapelIO.halt()`.
     */
    proc get(): retType {
      if !isValid() then halt("get() called on invalid future");
      chpl_taskWaitFor(classRef.handle);
      //classRef.state.waitFor(true);
      return classRef.value;
    }
    
    pragma "no doc"
    proc set(value: retType) {
      if !isValid() then halt("set() called on invalid future");
      classRef.value = value;
      var oldState = classRef.state.testAndSet();
      if oldState then halt("set() called more than once on a future");
    }

    /*
      Test whether the result of the future is available.

      If the future is not valid, this call will :proc:`~ChapelIO.halt()`.
     */
    proc isReady(): bool {
      if !isValid() then halt("isReady() called on invalid future");
      return classRef.state.peek();
    }

    /*
      Test whether the future is valid. For more,
      :ref:`see above <valid-futures>`.
     */
    inline proc isValid(): bool {
      return ((classRef != nil) && classRef.valid);
    }

    /*
      Asynchronously execute a function as a continuation of the future.

      The function argument `taskFn` must take a single argument of type
      `retType` (i.e., the return type of the parent future) and will be
      executed when the parent future's value is available.

      If the parent future is not valid, this call will :proc:`~ChapelIO.halt()`.

      :arg taskFn: The function to invoke as a continuation.
      :returns: A future of the return type of `taskFn`
     */
    proc andThen(taskFn) {
      /*
      if !canResolveMethod(taskFn, "this", retType) then
        compilerError("andThen() task function arguments are incompatible with parent future return type");
      */
      if !isValid() then halt("andThen() called on invalid future");
      if !canResolveMethod(taskFn, "retType") then
        compilerError("cannot determine return type of andThen() task function");
      if !canResolveMethod(taskFn, "cAndThenFnPtr") then
        compilerError("cannot determine return C Function Pointer of async() task function");
      var f: Future(taskFn.retType);
      f.classRef.valid = true;
      var n: c_uint = 1;
      var args_sizes: [1..n+1] uint(64);
      if isStringType(this.retType) {
        // strings will be c_ptr(c_char) so size will be the same as that of
        // c_void_ptr
        args_sizes(1) = c_sizeof(c_void_ptr);
      }
      else {
        args_sizes(1) = c_sizeof(c_void_ptr);
        //args_sizes(1) = numBytes(this.retType);
      }
      // return value will be a c_void_ptr
      args_sizes(n+1) = c_sizeof(c_void_ptr);
      var args_list = (c_ptrTo(this.classRef.value), c_ptrTo(f.classRef.value));
      var dep_handles: [1..2] uint(64);
      dep_handles[1] = this.classRef.handle;
      f.classRef.handle = chpl_taskLaunch(c_ptrTo(taskFn.cAndThenFnPtr), n+1, 
                          args_sizes, c_ptrTo(args_list),
                          dep_handles, 1);

      //begin f.set(taskFn(this.get()));
      return f;
    }

    /*
      Asynchronously execute a function as a continuation of the future.

      The function argument `taskFn` must take a single argument of type
      `retType` (i.e., the return type of the parent future) and will be
      executed when the parent future's value is available.

      If the parent future is not valid, this call will :proc:`~ChapelIO.halt()`.

      :arg taskFn: The function to invoke as a continuation.
      :returns: A future of the return type of `taskFn`
     */
    proc andThen(kernelName: string, type retType) {
      /*
      if !canResolveMethod(taskFn, "this", retType) then
        compilerError("andThen() task function arguments are incompatible with parent future return type");
      */
      if !isValid() then halt("andThen() called on invalid future");
      var f: Future(retType);
      f.classRef.valid = true;
      var n: c_uint = 1;
      var args_sizes: [1..n+1] uint(64);
      if isStringType(this.retType) {
        // strings will be c_ptr(c_char) so size will be the same as that of
        // c_void_ptr
        args_sizes(1) = c_sizeof(c_void_ptr);
      }
      else {
        args_sizes(1) = c_sizeof(c_void_ptr);
        // args_sizes(1) = numBytes(this.retType);
      }
      // return value will be a c_void_ptr
      args_sizes(n+1) = c_sizeof(c_void_ptr);
      var args_list = (c_ptrTo(this.classRef.value), c_ptrTo(f.classRef.value));
      var dep_handles: [1..2] uint(64);
      dep_handles[1] = this.classRef.handle;

      var hsaco_kernelName = "wrap_kernel_" + kernelName;
      f.classRef.handle = chpl_gpuTaskLaunch(hsaco_kernelName.c_str(), 
                              n+1, args_sizes,
                              c_ptrTo(args_list), dep_handles, 1);

      //begin f.set(taskFn(this.get()));
      return f;
    }

    pragma "no doc"
    proc acquire(newRef: FutureClass) {
      if isValid() then halt("acquire(newRef) called on valid future!");
      classRef = newRef;
      classRef.incRefCount();
    }

    pragma "no doc"
    proc acquire() {
      if classRef == nil then halt("acquire() called on nil future");
      classRef.incRefCount();
    }

    pragma "no doc"
    proc release() {
      if classRef == nil then halt("release() called on nil future");
      var rc = classRef.decRefCount();
      if rc == 1 {
        delete classRef;
        classRef = nil;
      }
    }

  } // record Future

  pragma "no doc"
  pragma "init copy fn"
  proc chpl__initCopy(x: Future) {
    x.acquire();
    return x;
  }

  pragma "no doc"
  pragma "auto copy fn"
  proc chpl__autoCopy(x: Future) {
    x.acquire();
    return x;
  }

  pragma "no doc"
  proc =(ref lhs: Future, rhs: Future) {
    if lhs.classRef == rhs.classRef then return;
    if lhs.classRef != nil then
      lhs.release();
    lhs.acquire(rhs.classRef);
  }

  pragma "no doc"
  proc getArgs(arg) {
    return (arg,);
  }
 
  pragma "no doc"
  proc getArgs(arg, args...) {
    return (arg, (...getArgs((...args))));
  }

  /*
    Asynchronously execute a function (taking no arguments) and return a
    :record:`Future` that will eventually hold the result of the function call.

    :arg taskFn: A function taking no arguments
    :returns: A future of the return type of `taskFn`
   */
  proc async(taskFn) {
    if !canResolveMethod(taskFn, "this") then
      compilerError("async() task function (expecting arguments) provided without arguments");
    if !canResolveMethod(taskFn, "retType") then
      compilerError("cannot determine return type of andThen() task function");
    if !canResolveMethod(taskFn, "cAsyncFnPtr") then
      compilerError("cannot determine return C Function Pointer of async() task function");
    var f: Future(taskFn.retType);
    f.classRef.valid = true;
    var n: c_uint = 0;
    var args_sizes: [1..n+1] uint(64);
    // return value will be a c_void_ptr
    args_sizes(n+1) = c_sizeof(c_void_ptr);
    var args_list = (c_ptrTo(f.classRef.value));
    var dep_handles: [1..2] uint(64);
    dep_handles[1] = chpl_nullTaskID;
    f.classRef.handle = chpl_taskLaunch(c_ptrTo(taskFn.cAsyncFnPtr), n+1, args_sizes, c_ptrTo(args_list), 
                        dep_handles, 0);
    //begin f.set(taskFn());
    return f;
  }

  /*
    Asynchronously execute a function (taking arguments) and return a
    :record:`Future` that will eventually hold the result of the function call.

    :arg taskFn: A function taking arguments with types matching `args...`
    :arg args...: Arguments to `taskFn`
    :returns: A future of the return type of `taskFn`
   */
  proc async(taskFn, args...?n) {
    if !canResolveMethod(taskFn, "this", (...args)) then
      compilerError("async() task function provided with mismatching arguments");
    if !canResolveMethod(taskFn, "retType") then
      compilerError("cannot determine return type of async() task function");
    if !canResolveMethod(taskFn, "cAsyncFnPtr") then
      compilerError("cannot determine return C Function Pointer of async() task function");
    var f: Future(taskFn.retType);
    f.classRef.valid = true;
    var args_sizes: [1..n+1] uint(64);
    for param i in 1..n {
      var t: bool = isStringType(args(i).type);
      if isStringType(args(i).type) {
        // strings will be c_ptr(c_char) so size will be the same as that of
        // c_void_ptr
        args_sizes(i) = c_sizeof(c_void_ptr);
      }
      else {
        args_sizes(i) = numBytes(args(i).type);
      }
    }
    // return value will be a c_void_ptr
    args_sizes(n+1) = c_sizeof(c_void_ptr);
    var args_list = ((...getArgs((...args))), c_ptrTo(f.classRef.value));
    var dep_handles: [1..2] uint(64);
    dep_handles[1] = chpl_nullTaskID;
    f.classRef.handle = chpl_taskLaunch(c_ptrTo(taskFn.cAsyncFnPtr), n+1, args_sizes,
                        c_ptrTo(args_list), dep_handles, 0);
    //begin f.set(taskFn((...args)));
    return f;
  }

  /*
    Asynchronously execute a function (taking arguments) and return a
    :record:`Future` that will eventually hold the result of the function call.

    :arg kernelName: OpenCL kernel name
    :arg args...: Arguments to `kernelName`
    :returns: A future of the return type of `kernelName`
   */
  proc async(kernelName: string, type retType, args...?n) {
    var f: Future(retType);
    f.classRef.valid = true;
    var args_sizes: [1..n+1] uint(64);
    for param i in 1..n {
      var t: bool = isStringType(args(i).type);
      if isStringType(args(i).type) {
        // strings will be c_ptr(c_char) so size will be the same as that of
        // c_void_ptr
        args_sizes(i) = c_sizeof(c_void_ptr);
      }
      else {
        args_sizes(i) = numBytes(args(i).type);
      }
    }
    // return value will be a c_void_ptr
    args_sizes(n+1) = c_sizeof(c_void_ptr);
    var args_list = ((...getArgs((...args))), c_ptrTo(f.classRef.value));
    var dep_handles: [1..2] uint(64);
    dep_handles[1] = chpl_nullTaskID;

    f.classRef.handle = chpl_gpuTaskLaunch(kernelName.c_str(), 
                              n+1, args_sizes,
                              c_ptrTo(args_list), dep_handles, 0);
    return f;
  }

  pragma "no doc"
  proc copyFutureValues(N: int, x:c_ptr(c_char), y: c_ptr(c_void_ptr), 
                        sz: c_ptr(uint(64))) {
    var cur_sz: uint(64) = 0;
    for i in 0..N-1 {
      memcpy(x + cur_sz, y[i], sz[i]);
      cur_sz += sz[i];
    }
    c_free(y);
    c_free(sz);
    return _defaultOf(int);
  }

  pragma "no doc"
  proc getAsyncFnPtr(taskFn) {
    return taskFn.cAsyncFnPtr;
  }

  pragma "no doc"
  proc getRetTypes(arg) type {
    return (arg.retType,);
  }

  pragma "no doc"
  proc getRetTypes(arg, args...) type {
    return (arg.retType, (...getRetTypes((...args))));
  }
   
  pragma "no doc"
  proc getRetHandles(arg) {
    return (arg.classRef.handle,);
  }

  pragma "no doc"
  proc getRetHandles(arg, args...) {
    return (arg.classRef.handle, (...getRetHandles((...args))));
  }
  
  pragma "no doc"
  proc getRetValuePtrs(arg) {
    return (c_ptrTo(arg.classRef.value),);
  }

  pragma "no doc"
  proc getRetValuePtrs(arg, args...) {
    return (c_ptrTo(arg.classRef.value), (...getRetValuePtrs((...args))));
  }

  pragma "no doc"
  proc getRetSizes(arg) {
    return (c_sizeof(arg.retType),);
  }

  pragma "no doc"
  proc getRetSizes(arg, args...) {
    return (c_sizeof(arg.retType), (...getRetSizes((...args))));
  }

  /*
    Bundle a set of futures and return a :record:`Future` that will hold a
    tuple of the results of its arguments (themselves futures).

    :arg futures...: A variable-length argument list of futures
    :returns: A future with a return type that is a tuple of the return type of
       the arguments
   */
  proc waitAll(futures...?N) {
    type retTypes = getRetTypes((...futures));
    var retValuePtrs = getRetValuePtrs((...futures));
    var retSizes = getRetSizes((...futures));
    var retHandles = getRetHandles((...futures));
    var f: Future(retTypes);
    f.classRef.valid = true;
    /*begin {
      var result: retTypes;
      for param i in 1..N do
        result[i] = futures[i].get();
      f.set(result);
    }*/

    var dep_handles: [1..N] uint(64);
    var cp_args_sizes: c_ptr(uint(64)) = c_malloc(uint(64), N);
    for i in 1..N {
      dep_handles[i] = retHandles[i];
      cp_args_sizes[i-1] = retSizes[i];
    }
    var cp_args_ptrs: c_ptr(c_void_ptr) = c_malloc(c_void_ptr, N);
    c_memcpy(cp_args_ptrs, c_ptrTo(retValuePtrs), N * c_sizeof(c_void_ptr)); 

    var dummy_ret: int;
    var args_list = (N, 
                    c_ptrTo(f.classRef.value), 
                    cp_args_ptrs, 
                    cp_args_sizes,
                    c_ptrTo(dummy_ret));
    var args_count: c_uint = args_list.size;
    var args_sizes: [1..args_count] uint(64) = (
                    c_sizeof(N.type),
                    c_sizeof(c_void_ptr),
                    c_sizeof(c_void_ptr),
                    c_sizeof(c_void_ptr),
                    c_sizeof(c_void_ptr));

    f.classRef.handle = chpl_taskLaunch(c_ptrTo(getAsyncFnPtr(copyFutureValues)), 
                          args_count, 
                          args_sizes, c_ptrTo(args_list),
                          dep_handles, N);

    return f;
  }

  pragma "no doc"
  inline proc &(f, g) {
    return waitAll(f, g);
  }

  proc _tuple.andThen(taskFn) where isTupleOfFutures(this) {
    if(this.size < 1) then
      compilerError("Tuple of Futures should have at least one object");
    var f: this.type;
    for i in 1..this.size {
      f(i) = this(i);
    }
    return waitAll((...f)).andThen(taskFn);
  }
    
  proc _tuple.andThen(kernelName: string, type retType) where isTupleOfFutures(this) {
    if(this.size < 1) then
      compilerError("Tuple of Futures should have at least one object");
    var f: this.type;
    for i in 1..this.size {
      f(i) = this(i);
    }
    return waitAll((...f)).andThen(kernelName, retType);
  }

  proc _tuple.get() where isTupleOfFutures(this) {
    if(this.size < 1) then
      compilerError("Tuple of Futures should have at least one object");
    var f: this.type;
    for i in 1..this.size {
      f(i) = this(i);
    }
    return waitAll((...f)).get();
  }

  proc isFuture(t) param where t:Future {
    return true;
  }

  proc isFuture(t) param {
    return false;
  }

  proc isTupleOfFutures(t) param {
    for param i in 1..t.size {
      if !isFuture(t(i)) then return false;
    }
    return true;
  }

} // module Futures
