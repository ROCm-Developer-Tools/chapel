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
 * A (naive) matrix multiply with RMO and CA matrices. In each case, all three matrices are laid out
 * in the same order.  
 * 
 * The validation routine compares the RMO and  CA outputs and prints "PASS" if the results match, 
 * "FAIL!" otherwise. . 
 *
 * Both MM operations are timed. On CPUs, CA is substantially slower than  RMO.
 * 
 * This version uses square matrices only. 
 *
 */

use Time;
use LayoutCA;

var t0: Timer;    // RMO 
var t1: Timer;    // on statement 


config var verbose = 0;

var rows = 1..128;
var cols = 1..128;

proc verify_results(C : [] real, Z : [] real) : bool {
  for i in rows {
    for j in cols {
      if (C(i,j) != Z(i,j)) then 
	return false;
    }
  }  
  return true;
}


/*
 *  RMO
 */
var domRowMajor : domain(2) = {rows, cols};
var A : [domRowMajor] real; 
var B : [domRowMajor] real; 
var C : [domRowMajor] real; 

for i in rows {
  for j in cols {
    A[i,j] = 17.0;
    B[i,j] = 2.0;
    C[i,j] = 0.0;
  }
}  

t0.start();
for i in rows do 
  for j in cols do 
    for k in cols do
      C[i,j] += A[i,k] * B[k,j];
t0.stop();

/*
 *  CA 
 */
var domCA : domain(2) dmapped CA() = {rows, cols};
var X : [domCA] real; 
var Y : [domCA] real; 
var Z : [domCA] real; 

for i in rows {
  for j in cols {
    X[i,j] = 17.0;
    Y[i,j] = 2.0;
    Z[i,j] = 0.0;
  }
}  

t1.start();
for i in rows do 
  for j in cols do 
    for k in cols do
      Z[i,j] += X[i,k] * Y[k,j];
t1.stop();


if (!verify_results(C,Z)) {
  writeln("FAIL!");
}
 else {
   writeln("PASS");
 }


if (verbose) then {
  writeln("RMO:\t ", t0.elapsed() * 1000, " ms");
  writeln("CMO:\t ", t1.elapsed() * 1000, " ms");
 }
 else {
   writeln(t0.elapsed() * 1000,",",t1.elapsed() * 1000); 
 }

t0.clear();
t1.clear();

