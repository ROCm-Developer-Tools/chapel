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

module LayoutTransforms {
  use Reflection;
  enum layoutType  { SOA = 0, AOS = 1};

  /* 
     Get number of elements for each field in this SoA
     and store in elements array. 
     Non-array fields have one element 

     Mainly needed to construct the ranges
  */
  proc getNumElements(const ref x:?t, ref elements) {
    param fields = numFields(x.type) - 1;

    for param i in 1 .. fields do {
      var field = getField(x, i); 
      if (isArray(field)) then 
	elements[i] = field.numElements;
      else
	elements[i] = 1; 

    }
  }

  /*
     Get ranges for each field. Doing this manually, because could not find something
     like field.range, which would have been convenient
  */
  proc getRanges(const ref x:?t, ref ranges, sizes) {
    param fields = numFields(x.type) - 1;

    var beg_index = 1;
    var offset = 0;
    for param i in 1..fields do {
      var field = getField(x, i);
      offset = offset + sizes[i];
      ranges[i] = beg_index .. offset;
      beg_index = beg_index + sizes[i];
    }
  }

  /*
     Get linear index in concatenated array
  */
  proc getLinearIndex(const ref x:?t, i : int, j : int)  {
    param fields = numFields(x.type) - 1;
    return (fields  * (j - 1)) + i;
  }
  

  /*
   *    map a 2D subcript (i,j) in SoA into a 2D subscript (i',j') in AoS
   */
  proc mapSoAtoAoS(const ref x:?t, ranges, ref i : int, ref j : int) : void {
    param fields = numFields(x.type) - 1;

    var idx = getLinearIndex(x, i, j);

    // find the field in which the element belongs
    for field_index in 1..fields do {
      if (ranges[field_index].member(idx)) then {
  	i = field_index;
  	break;
      }
    }

    // find the position within the field
    // TODO: general technique to support ranges starting from any value
    var rem = idx % ranges[i].length;
    if (rem) then
      j = rem;
    else
      j = ranges[i].length;
  }


  /* proc SoAtoAoS(type t) { */
  /*   recordType = t; */
  /* } */
}
