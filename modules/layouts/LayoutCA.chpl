/*
 * Copyright 2017 Advanced Micro Devices, Inc.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
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

/** 
 * This module implements a domain map that converts a rectangular array to the compressed-array 
 * layout. Details of the compressed-array transformation can be found in the following 
 * publication 
 * 
 * Apan Qasem, Ashwin M. Aji, Gregory Rodgers, "Characterizing data organization effects on 
 * heterogeneous memory architectures". CGO 2017: 160-170 
 * 
 * The code in this module draws heavily from time implementation of DefaultRectangular, an 
 * internal module in Chapel. 
 *
 * This domain map is a layout, i.e. it maps all indices to the current locale.
 *
 *
 * @author: Apan Qasem 
 * @date : 07/27/17
 */ 

config param chpl_dl_debug = false;
config param chpl_dl_validate = false;

/**
 *  Distribution descriptor class 
 *
 *  To declare a CA domain, invoke the ``CA`` constructor without arguments in 
 *  a `dmapped` clause. For example:

  .. code-block:: chapel

    use LayoutCA;
    var D: domain(2) dmapped CA() = {rows, cols};
    var A: [D] real;  // array in CMO

  .. code-block:: chapel

 * 
 * CA expects arrays to be two-dimensional. Higher ranked arrays will be supported
 * in future revisions. 
 * 
 * CA does not support Associative, Opaque or Sparse domains. 
 *  
 */
class CA: BaseDist {

  var tilesize : int;
  proc CA(t = 1 : int) {
    tilesize = t;
  }
  proc dsiNewRectangularDom(param rank: int, type idxType, param stridable: bool) {
      return new CADom(rank, idxType, stridable, this);
  }
 
  proc dsiClone() return this;
  
  proc dsiEqualDMaps(that: CA) param {
    return true;
  }
}
  
/** 
 * Domain descriptor class 
 * 
 */
class CADom: BaseRectangularDom {
  param rank: int;
  type idxType;
  param stridable : bool;
  var dist : CA;
  
  var ranges : rank * range(idxType, BoundedRangeType.bounded, stridable);

  proc CADom(param rank, type idxType, param stridable, dist) {
    if (rank != 2) then
      compilerError("CA currently only supports 2D rectangular domains"); 
    this.dist = dist;
    if chpl_dl_debug then 
      writeln("CA domain created.");
  }

  inline proc getTileSize() { return dist.tilesize; }
  proc setTileSize(t) { dist.tilesize = t; }
  proc dsiGetIndices() return ranges; 
  proc dsiSetIndices(x) { ranges = x; }


  proc dsiMyDist() return dist;

  proc dsiBuildArray(type eltType) {
    return new CAArr(eltType = eltType, rank = rank, idxType = idxType, 
			stridable = stridable, dom = this);
  }

  proc dsiDisplayRepresentation() {
    writeln("Display representation of CA domain");
  }

  proc dsiSerialWrite(f) {
    if chpl_dl_debug then  {
      writeln("Serial write of CA domain");
    }
    writeln(ranges);
  }

  /** get all ranges in domain */
  proc dsiDims()
    return ranges;

  /** get the range for particular dimension */
  proc dsiDim(d : int)
    return ranges(d);

  proc dsiNumIndices {
    var sum = 1:idxType;
    for param i in 1..rank do
      sum *= ranges(i).length;
    return sum;
  }

  proc dsiLow {
    if rank == 1 {
      return ranges(1).low;
    } 
    else {
      var result: rank*idxType;
      for param i in 1..rank do
	result(i) = ranges(i).low;
      return result;
    }
  }
  
  proc dsiHigh {
    if rank == 1 {
      return ranges(1).high;
    } else {
      var result: rank*idxType;
      for param i in 1..rank do
	result(i) = ranges(i).high;
      return result;
    }
  }

  iter these_help(param d: int) {
    if d == rank {
      for i in ranges(d) do
	yield i;
    } 
    else if d == rank - 1 {
      for i in ranges(d) do
	for j in these_help(rank) do
	  yield (i, j);
    } 
    else {
      for i in ranges(d) do
	for j in these_help(d+1) do
	  yield (i, (...j));
    }
  }
  
  iter these_help(param d: int, block) {
    if d == block.size {
      for i in block(d) do
	yield i;
    } 
    else if d == block.size - 1 {
      for i in block(d) do
	for j in these_help(block.size, block) do
	  yield (i, j);
    } 
    else {
      for i in block(d) do
	for j in these_help(d+1, block) do
	  yield (i, (...j));
    }
  }
  
  iter these(tasksPerLocale = dataParTasksPerLocale,
	     ignoreRunning = dataParIgnoreRunningTasks,
	     minIndicesPerTask = dataParMinGranularity,
	     offset=createTuple(rank, idxType, 0:idxType)) {
    if rank == 1 {
      for i in ranges(1) do
	yield i;
    } 
    else {
      for i in these_help(1) do
	yield i;
    }
  }
  
  proc dsiMember(ind: rank*idxType) {
    for param i in 1..rank do
      if !ranges(i).member(ind(i)) then
	return false;
    return true;
  }

  proc dsiBuildDom(param rank: int, type idxType, param stridable: bool,
		   ranges: rank*range(idxType,
				      BoundedRangeType.bounded,
				      stridable)) {
    var dom = new CADom(rank, idxType, stridable, dist);
    for i in 1..rank do
      dom.ranges(i) = ranges(i);
    return dom;
  }
  
}

/** 
 * Array descriptor class 
 */ 
class CAArr : BaseArr {
 
  type eltType;
  param rank: int;
  type idxType;
  param stridable: bool;
  
  type idxSignedType = chpl__signedType(idxType);
  var dom : CADom(rank = rank, idxType = idxType, stridable = stridable);
  
  var off: rank*idxType;
  var blk: rank*idxType;
  var str: rank*idxSignedType;
  var origin: idxType;
  var factoredOffs: idxType;
  
  var mdParDim: int;           //   array is chunked on this dimension
  var mdNumChunks: int;        //   number of chunks
  var mdRLo: idxType;          //   chunking dim .low
  var mdRHi: idxType;          //       "     "  .high
  var mdRStr: idxType;         //       "     "  .stride
  var mdRLen: idxType;         //       "     "  .length
  var mdBlk: idxType;          //       "     "  block factor when sliced
  var mdAlias: bool;           //   is this an alias of another array?
  
  pragma "local field"
    var mData : _ddata(_multiData(eltType=eltType,
				  idxType=idxType));
  
  var noinit_data: bool = false;
  
  // 'dataAllocRange' is used by the array-vector operations (e.g. push_back,
    // pop_back, insert, remove) to allow growing or shrinking the data
    // buffer in a doubling/halving style.  If it is used, it will be the
    // actual size of the 'data' buffer, while 'dom' represents the size of
    // the user-level array.
    var dataAllocRange: range(idxType);

  proc CAArr(type eltType, param rank, type idxType, param stridable, dist) {
    writeln("CA array created");
  }

  proc dsiGetBaseDom() return dom;

  /** when is this called? */
  proc dsiDisplayRepresentation() {
    writeln("Display representation of CA domain");
  }

  pragma "local field"
    var data : _ddata(eltType);
  
  pragma "local field"
    var shiftedData : _ddata(eltType);


  inline proc transpose(ind : rank * idxType) {
    var tmp : idxType;
    tmp = ind(1);
    ind(1) = ind(2);
    ind(2) = tmp;
  }

  inline proc tile(ind : rank * idxType) : int {

    /**
     *  Tile size conditions 
     *      (i) tilesize >= fields       // at least one element from each field per tile 
     *     (ii) tilesize % fields == 0   // do not allow uneven tiles 
     * 
     * if conditions are not met, do not tile 
     */
    var tilesize = dom.getTileSize();
    var fields = dom.dsiDim(1).length;   // number of rows in transposed array
    if ((tilesize < fields) || (tilesize % fields != 0)) then {
      dom.setTileSize(0);
      return 0;
    }


    var i = ind(1);
    var j = ind(2);

    if (chpl_dl_debug) then 
      writeln("tile index in: (", i, ",", j, ") ");

    var elts = dom.dsiDim(2).length;      // number of cols in transposed array
    var subtile_size = tilesize / fields;


    // find out which tile this elements belongs to 
    var tilenum = j / subtile_size;
    if (!(j % subtile_size)) then
      tilenum = tilenum - 1;

    // find out the starting position of the tile (linear order) 
    var tile_base_pos = (tilenum  * tilesize) + 1; // assume lowdim = 1

    var tile_offset = subtile_size * (i - 1); // i = row num = field num
    var subtile_offset = j % subtile_size;
    if (subtile_offset == 0) then // last position in subtile
      subtile_offset = subtile_size;

    if (chpl_dl_debug) then {
      writeln("fields = ", fields, " elements = ", elts, " subtile = ", subtile_size); 
      writeln("tile number = ", tilenum, " tile begin pos = ", tile_base_pos);
      writeln("tile offset = ", tile_offset, " subtile offset = ", subtile_offset);
    }

    // adjust tile begin position for lower bound of 1 
    j = (tile_base_pos - 1) + tile_offset + subtile_offset;
    var linear_index = j;

    // map to col number 
    j = j % elts;
    if (!j) then
      j = elts;
      
    // map to row number 
    i = tile_base_pos / elts;
    if (tile_base_pos % elts) then
      i = i + 1;
    
    if (chpl_dl_debug) then
      writeln("tile index out: (", i, ",", j, ") ");
    
    ind(1) = i;
    ind(2) = j;
    
    return linear_index;
  }

  /** 
   * dataChunking implemented for NUMA optimization. Introduced too much overhead and was 
   * discontinued. Currently disabled via param defRectDisableMultiDData. Can ignore for 
   * data layout transformations. (correspondence with Greg Titus)
   */
  inline proc dataChunk(i) ref {
    if defRectSimpleDData then
      return data;
    else {
      return mData(i).data;
    }
  }
  inline proc theDataChunk(i: idxType) ref {
    if defRectSimpleDData {
      if earlyShiftData && !stridable then {
	return shiftedData;
      }
      else {
	return data;
      }
    } else {
      if earlyShiftData && !stridable then
	return mData(i).shiftedData;
      else
	return mData(i).data;
    }
  }
  inline proc theDataChunk(i: integral) ref {
    return theDataChunk(i: idxType);
  }
  
  inline proc theData(i: idxType) ref where defRectSimpleDData {
    return theDataChunk(0)(i);
  }  
  inline proc theData(i: (int, idxType)) ref where !defRectSimpleDData {
    return theDataChunk(i(1))(i(2));
  }  

  inline proc theData(chunk: int, i: idxType) ref where !defRectSimpleDData {
    return theDataChunk(chunk)(i);
  }

  /** 
   * Accessor functions. These functions are called when the programmer references an array.  
   * 
   * Want to ensure that indices are transformed to match the transformed domain. For example, 
   * If domain has been transposed (i.e., row-major to col-major) then indices needs to be 
   * transposed as well. 
   * 
   * dsiAccess() can be called many times. There is code
   * in these modules that attempt to minimize the number of dsiAccess() calls to reduce overhead. 
   * So adding a call inside dsiAccess() may not be most efficient. 
   */

  // no transformation for rank 1 indices (maybe sparsity?)
  inline proc dsiAccess(ind: idxType ...1) ref
    where rank == 1 {
    return dsiAccess(ind);
  }

  // no transformation for rank 1 indices (maybe sparsity?)
  inline proc dsiAccess(ind: idxType ...1) 
    where rank == 1 && !shouldReturnRvalueByConstRef(eltType) {
    return dsiAccess(ind);
  }

  // no transformation for rank 1 indices (maybe sparsity?)
  inline proc dsiAccess(ind: idxType ...1) const ref
    where rank == 1 && shouldReturnRvalueByConstRef(eltType) {
    return dsiAccess(ind);
  }

  inline proc dsiAccess(ind : rank*idxType) ref {
    // transpose indices before moving forward. 
    // rest of the code only sees tranformed indices
    transpose(ind);
    tile(ind);
    if boundsChecking then
      if !dom.dsiMember(ind) {
	// Note -- because of module load order dependency issues,
	// the multiple-arguments implementation of halt cannot
	// be called at this point. So we call a special routine
	// that does the right thing here.
	halt("array index out of bounds: " + _stringify_tuple(ind));
      }


    var dataInd = getDataIndex(ind);
    if chpl_dl_debug then  {
      writeln("dsiAccess : write");
      write("(", dataInd - blk(1), ") " );
    }
    return theData(dataInd);
  }
  
  // Unsure when this disAccess() is invoked. Do not transpose. Need to revisit. 
  inline proc dsiAccess(ind : rank*idxType)
    where !shouldReturnRvalueByConstRef(eltType) {

    // transpose indices before moving forward. 
    // rest of the code only sees tranformed indices
    transpose(ind);
    tile(ind);
    if chpl_dl_debug then 

    if boundsChecking then
      if !dom.dsiMember(ind) {
	halt("array index out of bounds: " + _stringify_tuple(ind));
      }
    var dataInd = getDataIndex(ind);
    if chpl_dl_debug then {
      writeln("dsiAccess() : read ");
      write("(", dataInd - blk(1), ") " );
    }
    return theData(dataInd);
  }
  
  inline proc dsiAccess(ind : rank*idxType) const ref
    where shouldReturnRvalueByConstRef(eltType) {
    // transpose indices before moving forward. 
    // rest of the code only sees tranformed indices
    transpose(ind);
    tile(ind);
    if boundsChecking then
      if !dom.dsiMember(ind) {
	halt("array index out of bounds: " + _stringify_tuple(ind));
      }
    var dataInd = getDataIndex(ind);
    if chpl_dl_debug then {
      writeln("dsiAccess() : unknown ");
      write("(", dataInd - blk(1), ") " );
    }
    return theData(dataInd);
  }


  /** 
   * Iterators 
   * 
   * Iterators call dsiAccess() methods. Claim that no change is necessary in the iterators 
   * for implementing the domain map transformations. 
   */
  iter these(tasksPerLocale:int = dataParTasksPerLocale,
	     ignoreRunning:bool = dataParIgnoreRunningTasks,
	     minIndicesPerTask:int = dataParMinGranularity)
    ref where defRectSimpleDData {
    if rank == 1 {
      // This is specialized to avoid overheads of calling dsiAccess()
      if !dom.stridable {
	// Ideally we would like to be able to do something like
	// "for i in first..last by step". However, right now that would
	// result in a strided iterator which isn't as optimized. It would
	// also add a range constructor, which in tight loops is pretty
	// expensive. Instead we use a direct range iterator that is
	// optimized for positively strided ranges. It should be just as fast
	// as directly using a "c for loop", but it contains code check for
	// overflow and invalid strides as well as the ability to use a less
	// optimized iteration method if users are concerned about range
	// overflow.
	const first = getDataIndex(dom.dsiLow);
	const second = getDataIndex(dom.dsiLow+1);
	const step = (second-first);
	const last = first + (dom.dsiNumIndices-1) * step;
	for i in chpl_direct_pos_stride_range_iter(first, last, step) {
	  yield theData(i);
	}
      } 
      else {
	const stride = dom.ranges(1).stride: idxType,
	start  = dom.ranges(1).first,
	first  = getDataIndex(start),
	second = getDataIndex(start + stride),
	step   = (second-first):idxSignedType,
	last   = first + (dom.ranges(1).length-1) * step:idxType;
	if step > 0 then
	  for i in first..last by step do
	    yield data(i);
	else
	  for i in last..first by step do
	    yield data(i);
      }
    } else {
      for i in dom do
	yield dsiAccess(i);
    }
  }
  
  iter these(param tag: iterKind,
	     tasksPerLocale = dataParTasksPerLocale,
	     ignoreRunning = dataParIgnoreRunningTasks,
	     minIndicesPerTask = dataParMinGranularity)
    ref where tag == iterKind.standalone && defRectSimpleDData {
    for i in dom.these(tag, tasksPerLocale,
		       ignoreRunning, minIndicesPerTask) {
      yield dsiAccess(i);
    }
  }
  
  iter these(param tag: iterKind,
	     tasksPerLocale = dataParTasksPerLocale,
	     ignoreRunning = dataParIgnoreRunningTasks,
	     minIndicesPerTask = dataParMinGranularity)
    where tag == iterKind.leader && defRectSimpleDData {
    for followThis in dom.these(tag,
				tasksPerLocale,
				ignoreRunning,
				minIndicesPerTask) do
      yield followThis;
  }
  
  iter these(param tag: iterKind, followThis,
	     tasksPerLocale = dataParTasksPerLocale,
	     ignoreRunning = dataParIgnoreRunningTasks,
	     minIndicesPerTask = dataParMinGranularity)
    ref where tag == iterKind.follower && defRectSimpleDData {
    
    for i in dom.these(tag=iterKind.follower, followThis,
		       tasksPerLocale,
		       ignoreRunning,
		       minIndicesPerTask) do
      yield dsiAccess(i);
  }
  
  
  /** 
   * These methods are called from dsiAccess() So will see the transformed indices.  
   * Should not apply transformation to the indices again. 
   * One exception is the call directly from the iterator these(...)
   * Should that be handled separatately?
   */
  inline proc getDataIndex(ind: idxType ...1,
			   param getShifted = true,
			   param getChunked = !defRectSimpleDData)
    where rank == 1
    return getDataIndex(ind, getShifted=getShifted, getChunked=getChunked);
  
  inline proc getDataIndex(ind: rank*idxType,
			   param getShifted = true,
			   param getChunked = !defRectSimpleDData) {
    param chunkify = !defRectSimpleDData && getChunked;
    
    if stridable {
      inline proc chunked_dataIndex(sum, str) {
	if mdNumChunks == 1 {
	  return (0, sum);
	} else {
	  const chunk = mdInd2Chunk(ind(mdParDim));
	  return (chunk, sum - mData(chunk).dataOff);
	}
      }
      
      var sum = origin;
      // the ind(), off(), blk() etc. match the transformed domain. So nothing to do here ...
      for param i in 1..rank do
          sum += (ind(i) - off(i)) * blk(i) / abs(str(i)):idxType;
        if chunkify then
          return chunked_dataIndex(sum, str=abs(str(mdParDim)):idxType);
        else
          return sum;
    } 
    else {
      inline proc chunked_dataIndex(sum) {
	if mdNumChunks == 1 {
	  return (0, sum);
	} else {
	  const chunk = mdInd2Chunk(ind(mdParDim));
	  return (chunk, sum - mData(chunk).dataOff);
	}
      }
      
      param wantShiftedIndex = getShifted && earlyShiftData;
      
      // optimize common case to get cleaner generated code
      if (rank == 1 && wantShiftedIndex) {
	if __primitive("optimize_array_blk_mult") {
	  if chunkify then
	    return chunked_dataIndex(ind(1));
	  else
	    return ind(1);
	} else {
	  if chunkify then
	    return chunked_dataIndex(ind(1) * blk(1));
	  else
	    return ind(1) * blk(1);
	}
      } else {
	//	var sum = if wantShiftedIndex then 0:idxType else origin;
	var sum = 0;
	// If we detect that blk is never changed then then blk(rank) == 1.
	// Knowing this, we need not multiply the final ind(...) by anything.
	// This relies on us marking every function that modifies blk
	if __primitive("optimize_array_blk_mult") {
	  for param i in 1..rank-1 {	    
	    sum += ind(i) * blk(i);
	  }
	  sum += ind(rank);
	} else {
	  for param i in 1..rank {
	    sum += ind(i) * blk(i);
	  }
	}
	if !wantShiftedIndex then sum -= factoredOffs;
	if chunkify then
	  return chunked_dataIndex(sum);
	else
	  return sum;
      }
    }
  }
  
  /**
   * The following three do not operate on the indices only the domain which has already 
   * been transformed. So no need to change these 
   */
  // This is very conservative (i.e., will generally assume non-contiguous)
  proc isDataContiguous() {

    for param dim in 1..rank do
      if off(dim)!= dom.dsiDim(dim).first then return false;

    if blk(rank) != 1 then return false;

    for param dim in 1..(rank-1) by -1 do
      if blk(dim) != blk(dim+1)*dom.dsiDim(dim+1).length then return false;

    // Strictly speaking a multi-ddata array isn't contiguous, but
    // nevertheless we do support bulk transfer on such arrays, so
    // here we ignore single- vs. multi-ddata.

    return true;
  }

  proc computeFactoredOffs() {
    factoredOffs = 0:idxType;
    for param i in 1..rank do {
      factoredOffs = factoredOffs + blk(i) * off(i);
    }
  }
  
  inline proc initShiftedData() {
    if earlyShiftData && !stridable {
      // Lydia note 11/04/15: a question was raised as to whether this
      // check on dsiNumIndices added any value.  Performance results
      // from removing this line seemed inconclusive, which may indicate
      // that the check is not necessary, but it seemed like unnecessary
      // work for something with no immediate reward.
      if dom.dsiNumIndices > 0 {
	const shiftDist = if isIntType(idxType) then
	  origin - factoredOffs
	  else
	    // Not bothering to check for over/underflow
	  origin:idxSignedType - factoredOffs:idxSignedType;
	if defRectSimpleDData {
	  shiftedData = _ddata_shift(eltType, dataChunk(0), shiftDist);
	} else {
	  for i in 0..#mdNumChunks {
	    mData(i).shiftedData = _ddata_shift(eltType, mData(i).data,
						shiftDist);
	  }
	}
      }
    }
  }
  

  /** 
   * initialize() 
   * This is where the domain transformation happens 
   */
  // change name to setup and call after constructor call sites
  // we want to get rid of all initialize functions everywhere
  proc initialize() {
    if (chpl_dl_debug) then 
      chpl_debug_writeln("Transposing domain ...");
    
    var tmp : range;
    tmp = dom.dsiDim(1);
    dom.ranges(1) = dom.dsiDim(2);
    dom.ranges(2) = tmp;
    
    if noinit_data == true then return;
    for param dim in 1..rank {
      off(dim) = dom.dsiDim(dim).alignedLow;
        str(dim) = dom.dsiDim(dim).stride;
      }
      blk(rank) = 1:idxType;
      for param dim in 1..(rank-1) by -1 do
        blk(dim) = blk(dim+1) * dom.dsiDim(dim+1).length;
      computeFactoredOffs();
      var size = blk(1) * dom.dsiDim(1).length;

      if defRectSimpleDData {
        data = _ddata_allocate(eltType, size);
      } else {
        //
        // Checking the size first (and having a large-ish size hurdle)
        // prevents us from calling the pure virtual getChildCount() in
        // ChapelLocale, when we're setting up arrays in the locale model
        // and thus here.getChildCount() isn't available yet.
        //
        if (size < defRectArrMultiDDataSizeThreshold
            || here.getChildCount() < 2) {
          mdParDim = 1;
          mdNumChunks = 1;
        }
        else {
          const (numChunks, parDim) =
            _computeChunkStuff(here.getChildCount(), ignoreRunning=true,
                               minSize=1, ranges=dom.ranges);
          if numChunks == 0 {
            mdParDim = 1;
            mdNumChunks = 1;
          } else {
            mdParDim = parDim;
            mdNumChunks = numChunks;
          }
        }
        mdRLo = dom.dsiDim(mdParDim).alignedLow;
        mdRHi = dom.dsiDim(mdParDim).alignedHigh;
        mdRStr = abs(dom.dsiDim(mdParDim).stride):idxType;
        mdRLen = dom.dsiDim(mdParDim).length;
        mdBlk = 1;
        mData = _ddata_allocate(_multiData(eltType=eltType,
                                           idxType=idxType),
                                mdNumChunks);

        //
        // If just a single chunk then get memory from anywhere but if
        // more then get each chunk's memory from the corresponding
        // sublocale.
        //
        if mdNumChunks == 1 {
          if stridable then
            mData(0).pdr = dom.dsiDim(mdParDim).low..dom.dsiDim(mdParDim).high
                           by dom.dsiDim(mdParDim).stride;
          else
            mData(0).pdr = dom.dsiDim(mdParDim).low..dom.dsiDim(mdParDim).high;
          mData(0).data = _ddata_allocate(eltType, size);
        } else {
          var dataOff: idxType = 0;
          for i in 0..#mdNumChunks do local on here.getChild(i) {
            mData(i).dataOff  = dataOff;
            const (lo, hi) = mdChunk2Ind(i);
            if stridable then
              mData(i).pdr = lo..hi by dom.dsiDim(mdParDim).stride;
            else
              mData(i).pdr = lo..hi;
            const chunkSize = size / mdRLen * mData(i).pdr.length;
            mData(i).data = _ddata_allocate(eltType, chunkSize);
            dataOff += chunkSize;
          }
        }
      }

      initShiftedData();
      if rank == 1 && !stridable then
        dataAllocRange = dom.dsiDim(1);
    }


  /**
   * I/O functions call dsiAccess() methods and reference the domain. Nothing to change. 
   */
  proc dsiSerialReadWrite(f) {

    if chpl_dl_debug then 
      writeln("CA array serial write"); 

    proc writeSpaces(dim:int) {
      for i in 1..dim {
        f <~> new ioLiteral(" ");
      }
    }

    proc recursiveArrayWriter(in idx: rank*idxType, dim=rank, in last=false) {
      var binary = f.binary();
      var arrayStyle = f.styleElement(QIO_STYLE_ELEMENT_ARRAY);
      var isspace = arrayStyle == QIO_ARRAY_FORMAT_SPACE && !binary;
      var isjson = arrayStyle == QIO_ARRAY_FORMAT_JSON && !binary;
      var ischpl = arrayStyle == QIO_ARRAY_FORMAT_CHPL && !binary;

      type strType = idxSignedType;
      var makeStridePositive = if dom.ranges(dim).stride > 0 then 1:strType else (-1):strType;

      if isjson || ischpl {
        if dim != 1 {
          f <~> new ioLiteral("[\n");
          writeSpaces(dim); // space for the next dimension
        } else f <~> new ioLiteral("[");
      }

      if dim == 1 {
        var first = true;
        for j in dom.ranges(dim) by makeStridePositive {
          if first then first = false;
          else if isspace then f <~> new ioLiteral(" ");
          else if isjson || ischpl then f <~> new ioLiteral(", ");
          idx(dim) = j;

	  if chpl_dl_validate then {
	    write("(", idx(2), ",", idx(1), ")"); 
	    write("(", idx(1), ",", idx(2), ")");
	    if (dom.getTileSize() == 0) then {
	      var dataInd = getDataIndex(idx);
	      write("(", idx(1), ",", idx(2), ")");
	      write("[", dataInd - blk(1), "] ");
	    }
	    else {
	      var tmp_idx = idx;
	      var linear_index = tile(tmp_idx);
	      write("(", tmp_idx(1), ",", tmp_idx(2), ")");
	      write("[", linear_index, "] ");
	    }
	  }
	  // idx already transposed; reversing before sending to dsiAccess(). 
	  var tmp_idx = idx;
	  transpose(tmp_idx);  
	  f <~> dsiAccess(tmp_idx);
	  
        }
      } 
      else {
        for j in dom.ranges(dim) by makeStridePositive {
          var lastIdx =  dom.ranges(dim).last;
          idx(dim) = j;

          recursiveArrayWriter(idx, dim=dim-1,
                               last=(last || dim == rank) && (j == dom.ranges(dim).alignedHigh));

          if isjson || ischpl {
            if j != lastIdx {
              f <~> new ioLiteral(",\n");
              writeSpaces(dim);
            }
          }
        }
      }

      if isspace {
        if !last && dim != rank {
          f <~> new ioLiteral("\n");
        }
      } else if isjson || ischpl {
        if dim != 1 {
          f <~> new ioLiteral("\n");
          writeSpaces(dim-1); // space for this dimension
          f <~> new ioLiteral("]");
        }
        else f <~> new ioLiteral("]");
      }
    }

    if false && !f.writing && !f.binary() &&
       rank == 1 && dom.ranges(1).stride == 1 &&
       dom._arrs.length == 1 {

      // resize-on-read implementation, disabled right now
      // until we decide how it should work.

      // Binary reads could also start out with a length.

      // Special handling for reading 1-D stride-1 arrays in order
      // to read them without requiring that the array length be
      // specified ahead of time.

      var binary = f.binary();
      var arrayStyle = f.styleElement(QIO_STYLE_ELEMENT_ARRAY);
      var isspace = arrayStyle == QIO_ARRAY_FORMAT_SPACE && !binary;
      var isjson = arrayStyle == QIO_ARRAY_FORMAT_JSON && !binary;
      var ischpl = arrayStyle == QIO_ARRAY_FORMAT_CHPL && !binary;

      if isjson || ischpl {
        f <~> new ioLiteral("[");
      }

      var first = true;

      var offset = dom.ranges(1).low;
      var i = 0;

      var read_end = false;

      while ! f.error() {
        if first {
          first = false;
          // but check for a ]
          if isjson || ischpl {
            f <~> new ioLiteral("]");
          } else if isspace {
            f <~> new ioNewline(skipWhitespaceOnly=true);
          }
          if f.error() == EFORMAT {
            f.clearError();
          } else {
            read_end = true;
            break;
          }
        } else {
          // read a comma or a space.
          if isspace then f <~> new ioLiteral(" ");
          else if isjson || ischpl then f <~> new ioLiteral(",");

          if f.error() == EFORMAT {
            f.clearError();
            // No comma.
            break;
          }
        }

        if i >= dom.ranges(1).size {
          // Create more space.
          var sz = dom.ranges(1).size;
          if sz < 4 then sz = 4;
          sz = 2 * sz;

          // like push_back
          const newDom = {offset..#sz};

          dsiReallocate( newDom );
          // This is different from how push_back does it
          // because push_back might lead to a call to
          // _reprivatize but I don't see how to do that here.
          dom.dsiSetIndices( newDom.getIndices() );
          dsiPostReallocate();
        }

        f <~> dsiAccess(offset + i);

        i += 1;
      }

      if ! read_end {
        if isjson || ischpl {
          f <~> new ioLiteral("]");
        }
      }

      {
        // trim down to actual size read.
        const newDom = {offset..#i};
        dsiReallocate( newDom );
        dom.dsiSetIndices( newDom.getIndices() );
        dsiPostReallocate();
      }

    } else {
      const zeroTup: rank*idxType;
      recursiveArrayWriter(zeroTup);
    }
  }


  /** 
   * dsiSerialWrite(f) gets invoked on a write() call to A,
   * Cannot invoke on object explicitly, i.e., A.dsiSerialWrite() is not allowed. An 
   * explanation was given by Michael Ferguson. 
   */ 
  proc dsiSerialWrite(f) {
    if chpl_dl_debug then 
      writeln("Serial write of CA Arr : ");
    
    var isNative = f.styleElement(QIO_STYLE_ELEMENT_IS_NATIVE_BYTE_ORDER): bool;

    if _isSimpleIoType(eltType) && f.binary() &&
       isNative && isDataContiguous() {
      // If we can, we would like to write the array out as a single write op
      // since _ddata is just a pointer to the memory location we just pass
      // that along with the size of the array. This is only possible when the
      // byte order is set to native or its equivalent.
      pragma "no prototype"
      extern proc sizeof(type x): size_t;
      const elemSize = sizeof(eltType);
      if boundsChecking then
        assert((dom.dsiNumIndices:uint*elemSize:uint) <= max(ssize_t):uint,
               "length of array to write is greater than ssize_t can hold");
      if defRectSimpleDData {
        const len = dom.dsiNumIndices;
        const src = theDataChunk(0);
        const idx = getDataIndex(dom.dsiLow);
        const size = len:ssize_t*elemSize:ssize_t;
        f.writeBytes(_ddata_shift(eltType, src, idx), size);
      } else {
        var indLo = dom.dsiLow;
        for chunk in 0..#mdNumChunks {
          if mData(chunk).pdr.length >= 0 {
            const src = theDataChunk(chunk);
            if isTuple(indLo) then
              indLo(mdParDim) = mData(chunk).pdr.low;
            else
              indLo = mData(chunk).pdr.low;
            const (_, idx) = getDataIndex(indLo);
            const blkLen = if mdParDim == rank
                           then 1
                           else blk(mdParDim) / blk(mdParDim+1);
            const len = mData(chunk).pdr.length * blkLen;
            const size = len:ssize_t*elemSize:ssize_t;
            f.writeBytes(_ddata_shift(eltType, src, idx), size);
          }
        }
      }
    } else {
      dsiSerialReadWrite(f);
    }
  }
}

