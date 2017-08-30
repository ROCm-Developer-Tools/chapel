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
 * Example showing the use of CA layout using arrays of strings
 *
 * To validate results, build program as follows
 *    chpl -o trans --set chpl_dl_validate=false ca_ex1.chpl
 *
 * This will produce the following output for the transformed array. 
 *
 *    (original index) (transposed index) (ca index) [linear index] value 
 */ 

use LayoutCA;

var rows = 1..4;
var cols = 1..8;

var domRMO : domain(2) = {rows, cols};
var domCA : domain(2) dmapped CA() = {rows, cols};

var A : [domRMO] string; 
var B : [domCA] string; 

var numrows = 4;
var numcols = 8;

/* initialize elements with value of linear index in RMO */ 
for i in rows {
  for j in cols {
    A[i,j] = "[" + i + "," +  j + "]";
    B[i,j] = "[" + i + "," +  j + "]";
  }
}

// print the two arrays. should be identical
writeln("Original array");
writeln(A);
writeln("CA array");
writeln(B);
