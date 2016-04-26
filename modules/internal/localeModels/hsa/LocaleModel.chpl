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

// LocaleModel.chpl
//
// This provides a hierarchical locale model architectural description.
// This locale has two sublocales.
// 0. The CPU sublocale contain memory and a
// multi-core processor with homogeneous cores, and we ignore any affinity
// (NUMA effects) between the processor cores and the memory.
// 1. The GPU sublocale allows execution on a target HSA GPU. Currently this
// sublocale shares its address space with the CPU sublocale / parent locale
// and does not  do any memory management.
// Documentation that is in the flat/numa locale code should not be repeated
// here.

module LocaleModel {

  param localeModelHasSublocales = true;

  use ChapelLocale;
  use DefaultRectangular;
  use ChapelNumLocales;
  use Sys;

  extern proc chpl_task_getRequestedSubloc(): int(32);

  config param debugLocaleModel = true;

  var doneCreatingLocales: bool = false;

  extern record chpl_localeID_t { };

  pragma "init copy fn"
  extern chpl__initCopy_chpl_rt_localeID_t
  proc chpl__initCopy(initial: chpl_localeID_t): chpl_localeID_t;

  extern var chpl_nodeID: chpl_nodeID_t;

  // Runtime interface for manipulating global locale IDs.
  extern
    proc chpl_rt_buildLocaleID(node: chpl_nodeID_t,
                               subloc: chpl_sublocID_t): chpl_localeID_t;

  extern
    proc chpl_rt_nodeFromLocaleID(loc: chpl_localeID_t): chpl_nodeID_t;

  extern
    proc chpl_rt_sublocFromLocaleID(loc: chpl_localeID_t): chpl_sublocID_t;

  // Compiler (and module code) interface for manipulating global locale IDs..
  pragma "insert line file info"
  proc chpl_buildLocaleID(node: chpl_nodeID_t, subloc: chpl_sublocID_t)
    return chpl_rt_buildLocaleID(node, subloc);

  pragma "insert line file info"
  proc chpl_nodeFromLocaleID(loc: chpl_localeID_t)
    return chpl_rt_nodeFromLocaleID(loc);

  pragma "insert line file info"
  proc chpl_sublocFromLocaleID(loc: chpl_localeID_t)
    return chpl_rt_sublocFromLocaleID(loc);

  class CPULocale : AbstractLocaleModel {
    const sid: chpl_sublocID_t;
    const name: string;

    proc chpl_id() return (parent:LocaleModel)._node_id; // top-level node id
    proc chpl_localeid() {
      warning("in CPU locale ID");
      return chpl_buildLocaleID((parent:LocaleModel)._node_id:chpl_nodeID_t,
                                sid);
    }
    proc chpl_name() return name;

    proc CPULocale() {
    }

    proc CPULocale(_sid, _parent) {
      warning("CREATING CPU LOCALE!");
      sid = _sid;
      name = "CPU"+sid;
      parent = _parent;
    }

    proc readWriteThis(f) {
      parent.readWriteThis(f);
      f <~> '.'+name;
    }

    proc getChildCount(): int { return 0; }
    iter getChildIndices() : int {
      halt("No children to iterate over.");
      yield -1;
    }
    proc addChild(loc:locale) {
      halt("Cannot add children to this locale type.");
    }
    proc getChild(idx:int) : locale { return nil; }
  }

  class GPULocale : AbstractLocaleModel {
    const sid: chpl_sublocID_t;
    const name: string;

    proc chpl_id() return (parent:LocaleModel)._node_id; // top-level node id
    proc chpl_localeid() {
      warning("in GPU locale ID");
      return chpl_buildLocaleID((parent:LocaleModel)._node_id:chpl_nodeID_t,
                                sid);
    }
    proc chpl_name() return name;

    proc GPULocale() {
    }

    proc GPULocale(_sid, _parent) {
      warning("CREATING GPU LOCALE!");
      sid = _sid;
      name = "GPU"+sid;
      parent = _parent;
    }

    proc readWriteThis(f) {
      parent.readWriteThis(f);
      f <~> '.'+name;
    }

    proc getChildCount(): int { return 0; }
    iter getChildIndices() : int {
      halt("No children to iterate over.");
      yield -1;
    }
    proc addChild(loc:locale) {
      halt("Cannot add children to this locale type.");
    }
    proc getChild(idx:int) : locale { return nil; }
  }

  const chpl_emptyLocaleSpace: domain(1) = {1..0};
  const chpl_emptyLocales: [chpl_emptyLocaleSpace] locale;


  //
  // A concrete class representing the parent Locale
  //
  class LocaleModel : AbstractLocaleModel {
    const callStackSize: size_t;
    const _node_id : int;
    const local_name : string;

    const numSublocales: int;
    //    var GPUSpace: domain(1);
    //    var GPU: [GPUSpace] GPULocale;
    var GPU: GPULocale;
    var CPU: CPULocale;

    proc LocaleModel() {
      if doneCreatingLocales {
        halt("Cannot create additional LocaleModel instances");
      }
      init();
    }

    proc LocaleModel(parent_loc : locale) {
      if doneCreatingLocales {
        halt("Cannot create additional LocaleModel instances");
      }
      parent = parent_loc;
      init();
    }

    proc chpl_id() return _node_id; // top-level node number
    proc chpl_localeid() {
      warning("in LocaleModel locale ID");
      return chpl_buildLocaleID(_node_id:chpl_nodeID_t, c_sublocid_any);
    }
    proc chpl_name() return local_name;


    proc readWriteThis(f) {
      f <~> new ioLiteral("LOCALE") <~> _node_id;
    }

    proc getChildSpace() {
      halt("error!");
      return {0..#numSublocales};
    }

    proc getChildCount() return 0;

    iter getChildIndices() : int {
      for idx in {0..#numSublocales} do // chpl_emptyLocaleSpace do
        yield idx;
    }

    proc getChild(idx:int) : locale {
      if idx == 1
        then return GPU;
      else
        return CPU;
    }

    iter getChildren() : locale  {
      halt("in here");
      for idx in {0..#numSublocales} {
        if idx == 1
          then yield GPU;
        else
          yield CPU;
      }
    }

    proc getChildArray() {
      halt ("in get child Array");
      return chpl_emptyLocales;
    }

    //------------------------------------------------------------------------{
    //- Implementation (private)
    //-
    proc init() {
      _node_id = chpl_nodeID: int;

      warning("HSA LocaleModel init");

      extern proc chpl_hsa_initialize(): c_int;
      var initHsa =  chpl_hsa_initialize();
      if (initHsa == 1) {
        halt("Could not initialize HSA");
      }

      var comm, spawnfn : c_string;
      extern proc chpl_nodeName() : c_string;
      if sys_getenv("CHPL_COMM".c_str(), comm) == 0 && comm == "gasnet" &&
        sys_getenv("GASNET_SPAWNFN".c_str(), spawnfn) == 0 && spawnfn == "L"
      then local_name = chpl_nodeName() + "-" + _node_id : string;
      else local_name = chpl_nodeName();

      extern proc chpl_task_getCallStackSize(): size_t;
      callStackSize = chpl_task_getCallStackSize();

      extern proc chpl_getNumLogicalCpus(accessible_only: bool): c_int;
      numCores = chpl_getNumLogicalCpus(true);

      extern proc chpl_task_getMaxPar(): uint(32);
      maxTaskPar = chpl_task_getMaxPar();

      numSublocales = 2;

      const origSubloc = chpl_task_getRequestedSubloc();

      chpl_task_setSubloc(0:chpl_sublocID_t);
      CPU = new CPULocale(0:chpl_sublocID_t, this);
      warning( "created " + CPU.name + " with sublocale id "+ CPU.sid);
      chpl_task_setSubloc(1:chpl_sublocID_t);

      GPU = new GPULocale(1:chpl_sublocID_t, this);
      warning( "created " + GPU.name + " with sublocale id "+ GPU.sid);
      chpl_task_setSubloc(origSubloc);
      //      GPUSpace = {0..0};
      //      for i in GPUSpace {
      //        GPU[i] = new GPULocale(i:chpl_sublocID_t, this);
      //      }
    }
    //------------------------------------------------------------------------}

    inline proc subloc return c_sublocid_any;
  }

  //
  // An instance of this class is used for the default 'rootLocale'.
  // See flat locale source (../flat/localeModel.chpl).
  class RootLocale : AbstractRootLocale {

    const myLocaleSpace: domain(1) = {0..numLocales-1};
    var myLocales: [myLocaleSpace] locale;

    proc RootLocale() {
      parent = nil;
      numCores = 0;
      maxTaskPar = 0;
    }

    // See flat locale source (../flat/localeModel.chpl).
    proc init() {
      forall locIdx in chpl_initOnLocales() {
        chpl_task_setSubloc(c_sublocid_any);
        const node = new LocaleModel(this);
        myLocales[locIdx] = node;
        numCores += node.numCores;
        maxTaskPar += node.maxTaskPar;
      }

      here.runningTaskCntSet(0);
    }

    // See flat locale source (../flat/localeModel.chpl).
    proc chpl_id() return numLocales;
    proc chpl_localeid() {
      return chpl_buildLocaleID(numLocales:chpl_nodeID_t, c_sublocid_none);
    }
    proc chpl_name() return local_name();
    proc local_name() return "rootLocale";

    proc readWriteThis(f) {
      f <~> name;
    }

    proc getChildCount() return this.myLocaleSpace.numIndices;

    proc getChildSpace() return this.myLocaleSpace;

    iter getChildIndices() : int {
      for idx in this.myLocaleSpace do
        yield idx;
    }

    proc getChild(idx:int) return this.myLocales[idx];

    iter getChildren() : locale  {
      for loc in this.myLocales do
        yield loc;
    }

    proc getDefaultLocaleSpace() return this.myLocaleSpace;
    proc getDefaultLocaleArray() return myLocales;

    proc localeIDtoLocale(id : chpl_localeID_t) {
      const node = chpl_nodeFromLocaleID(id);
      const subloc = chpl_sublocFromLocaleID(id);
      if (subloc == c_sublocid_none) || (subloc == c_sublocid_any) then
        return (myLocales[node:int]):locale;
      else
        return (myLocales[node:int].getChild(subloc:int)):locale;
    }
  }

  //////////////////////////////////////////
  //
  // utilities
  //
  inline
  proc chpl_getSubloc() {
    extern proc chpl_task_getSubloc(): chpl_sublocID_t;
    return chpl_task_getSubloc();
  }

  //////////////////////////////////////////
  //
  // support for memory management
  //

  // The allocator pragma is used by scalar replacement.
  pragma "allocator"
  pragma "locale model alloc"
  proc chpl_here_alloc(size:int, md:int(16)) {
    pragma "insert line file info"
      extern proc chpl_mem_alloc(size:int, md:int(16)) : opaque;
    return chpl_mem_alloc(size, md + chpl_memhook_md_num());
  }

  pragma "allocator"
  proc chpl_here_calloc(size:int, number:int, md:int(16)) {
    pragma "insert line file info"
      extern proc chpl_mem_calloc(number:int, size:int, md:int(16)) : opaque;
    return chpl_mem_calloc(number, size, md + chpl_memhook_md_num());
  }

  pragma "allocator"
  proc chpl_here_realloc(ptr:opaque, size:int, md:int(16)) {
    pragma "insert line file info"
      extern proc chpl_mem_realloc(ptr:opaque, size:int, md:int(16)) : opaque;
    return chpl_mem_realloc(ptr, size, md + chpl_memhook_md_num());
  }

  pragma "locale model free"
  proc chpl_here_free(ptr:opaque) {
    pragma "insert line file info"
      extern proc chpl_mem_free(ptr:opaque): void;
    chpl_mem_free(ptr);
  }


  //////////////////////////////////////////
  //
  // support for "on" statements
  //

  //
  // runtime interface
  //
  extern proc chpl_comm_fork(loc_id: int, subloc_id: int,
                             fn: int, args: c_void_ptr, arg_size: int(32));
  extern proc chpl_comm_fork_fast(loc_id: int, subloc_id: int,
                                  fn: int, args: c_void_ptr, args_size: int(32));
  extern proc chpl_comm_fork_nb(loc_id: int, subloc_id: int,
                                fn: int, args: c_void_ptr, args_size: int(32));
  extern proc chpl_ftable_call(fn: int, args: c_void_ptr): void;

  extern proc chpl_task_setSubloc(subloc: int(32));
  extern proc chpl_dummy(): void;

  //
  // regular "on"
  //
  pragma "insert line file info"
  export
  proc chpl_executeOn(loc: chpl_localeID_t, // target locale
                      fn: int,              // on-body function idx
                      args: c_void_ptr,     // function args
                      args_size: int(32)     // args size
                     ) {

    const node = chpl_nodeFromLocaleID(loc);
    const subloc = chpl_sublocFromLocaleID(loc);
    //if (subloc == 0) {
      //warning("executing on CPU");
    //}
    //else if (subloc == 1) {
      //warning("executing on GPU");
    //}

    if (node == chpl_nodeID) {
      const origSubloc = chpl_task_getRequestedSubloc();

      chpl_task_setSubloc(subloc);
      // don't call the runtime fork function if we can stay local
      chpl_ftable_call(fn, args);
      chpl_task_setSubloc(origSubloc);
      //warning("in ExecuteOn, after sublocal set to " + origSubloc:string);
    } else {
      chpl_comm_fork(node, chpl_sublocFromLocaleID(loc),
                     fn, args, args_size);
    }
  }

  //
  // fast "on" (doesn't do anything that could deadlock a comm layer,
  // in the Active Messages sense)
  //
  pragma "insert line file info"
  export
  proc chpl_executeOnFast(loc: chpl_localeID_t, // target locale
                          fn: int,              // on-body function idx
                          args: c_void_ptr,     // function args
                          args_size: int(32)    // args size
                         ) {
    //warning("in ExecuteOnFast");
    const node = chpl_nodeFromLocaleID(loc);
    const subloc = chpl_sublocFromLocaleID(loc);
    //if (subloc == 0) {
      //warning("executing on CPU");
    //}
    //else if (subloc == 1) {
      //warning("executing on GPU");
    //}
    if (node == chpl_nodeID) {
      const origSubloc = chpl_task_getRequestedSubloc();
      chpl_task_setSubloc(subloc);
      // don't call the runtime fast fork function if we can stay local
      chpl_ftable_call(fn, args);
      chpl_task_setSubloc(origSubloc);
    } else {
      chpl_comm_fork_fast(node, chpl_sublocFromLocaleID(loc),
                          fn, args, args_size);
    }
  }

  //
  // nonblocking "on" (doesn't wait for completion)
  //
  pragma "insert line file info"
  export
  proc chpl_executeOnNB(loc: chpl_localeID_t, // target locale
                        fn: int,              // on-body function idx
                        args: c_void_ptr,     // function args
                        args_size: int(32)    // args size
                       ) {
    //
    // If we're in serial mode, we should use blocking rather than
    // non-blocking "on" in order to serialize the forks.
    //
    //warning("in ExecuteOnNB");
    const node = chpl_nodeFromLocaleID(loc);
    if (node == chpl_nodeID) {
      if __primitive("task_get_serial") then
        // don't call the runtime nb fork function if we can stay local
        chpl_ftable_call(fn, args);
      else
        // We'd like to use a begin, but unfortunately doing so as
        // follows does not compile for --no-local:
        // begin chpl_ftable_call(fn, args);
        chpl_comm_fork_nb(node, chpl_sublocFromLocaleID(loc),
                          fn, args, args_size);
    } else {
      const subloc = chpl_sublocFromLocaleID(loc);
      if __primitive("task_get_serial") then
        chpl_comm_fork(node, subloc, fn, args, args_size);
      else
        chpl_comm_fork_nb(node, subloc, fn, args, args_size);
    }
  }

  //////////////////////////////////////////
  //
  // support for tasking statements: begin, cobegin, coforall
  //

  //
  // runtime interface
  //
  pragma "insert line file info"
  extern proc chpl_task_addToTaskList(fn: int, args: c_void_ptr, subloc_id: int,
                                      ref tlist: _task_list, tlist_node_id: int,
                                      is_begin: bool);
  extern proc chpl_task_processTaskList(tlist: _task_list);
  extern proc chpl_task_executeTasksInList(tlist: _task_list);
  extern proc chpl_task_freeTaskList(tlist: _task_list);

  //
  // add a task to a list of tasks being built for a begin statement
  //
  pragma "insert line file info"
  export
  proc chpl_taskListAddBegin(subloc_id: int,        // target sublocale
                             fn: int,               // task body function idx
                             args: c_void_ptr,           // function args
                             ref tlist: _task_list, // task list
                             tlist_node_id: int     // task list owner node
                            ) {
    chpl_task_addToTaskList(fn, args, subloc_id, tlist, tlist_node_id, true);
  }

  //
  // add a task to a list of tasks being built for a cobegin or coforall
  // statement
  //
  pragma "insert line file info"
  export
  proc chpl_taskListAddCoStmt(subloc_id: int(32),        // target sublocale
                              fn: int,               // task body function idx
                              args: c_void_ptr,           // function args
                              ref tlist: _task_list, // task list
                              tlist_node_id: int     // task list owner node
                             ) {
    chpl_task_addToTaskList(fn, args, subloc_id, tlist, tlist_node_id, false);
  }

  //
  // make sure all tasks in a list are known to the tasking layer
  //
  pragma "insert line file info"
  export
  proc chpl_taskListProcess(task_list: _task_list) {
    chpl_task_processTaskList(task_list);
  }

  //
  // make sure all tasks in a list have an opportunity to run
  //
  pragma "insert line file info"
  export
  proc chpl_taskListExecute(task_list: _task_list) {
    chpl_task_executeTasksInList(task_list);
  }

  //
  // do final cleanup for a task list
  //
  pragma "insert line file info"
  export
  proc chpl_taskListFree(task_list: _task_list) {
    chpl_task_freeTaskList(task_list);
  }
}
