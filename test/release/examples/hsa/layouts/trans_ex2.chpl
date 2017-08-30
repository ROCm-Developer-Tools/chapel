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
 * Example program to compare performance difference between RMO and CMO. 
 * 
 * The program performs a simple matrix copy operation. Source matrix is in RMO form. 
 * Destination matrix is in CMO. CMO performance is compared to an RMO-RMO copy. 
 *
 * The validation routine prints "PASS" if the copy is successful. 
 *
 * The GPU path is currently not functional. We are currently not able to generate code 
 * for GPU when using dmapped causes on arrays  
 * 
 * CMO should be about a factor of two slower on most CPU systems. 
 */
use Time;
use LayoutTranspose;

var t0: Timer;    // RMO 
var t1: Timer;    // on statement 
var t2: Timer;    // ...
var t3: Timer;    // CMO


config var IMGS = 64;
config var PIXELS = 64;
config var layout = "row";
config var verbose = 0;
config var agent = "CPU";
config var ITERS = 1;

var rows = 1..1024;
var cols = 1..1024;

var numrows = 4;
var numcols = 8;

proc verify_results(A : [] real, B : [] real) : bool {
  for i in rows {
    for j in cols {
      if (A(i,j) != B(i,j)) then 
	return false;
    }
  }  
  return true;
}

pragma "request gpu offload"
proc rowmajor(agent : string) {

  param CMO : bool = true;
  var domRowMajor : domain(2) = {rows, cols};
  var A : [domRowMajor] real; 
  var B : [domRowMajor] real; 

  for i in rows {
    for j in cols {
      A[i,j] = 17.0;
      B[i,j] = 0.0;
    }
  }  
  if (agent == "device") {
    t1.start();
    on (Locales[0]:LocaleModel).GPU do {
      t2.start();
      forall i in rows {
	for j in cols {
	  B[i,j] = A[i,j];
	}
      }
      t2.stop();
     }
     t1.stop();
   } 
   else {
     t1.start();
     on (Locales[0]:LocaleModel).CPU do {
       t2.start();
       forall i in rows {
	 for j in cols {
	   B[i,j] = A[i,j];
	 }
       }
       t2.stop();
     }
     t1.stop();
   }

  if (!verify_results(A,B)) { 
    writeln("FAIL!");  
  }
  else { 
    writeln("PASS");
  }
}


pragma "request gpu offload"
proc colmajor(agent: string) {

  var domColMajor : domain(2) dmapped Transpose() = {rows, cols};
  var A : [domColMajor] real; 
  var B : [domColMajor] real; 

  for i in rows {
    for j in cols {
      A[i,j] = 17.0;
      B[i,j] = 0.0;
    }
  }  
  if (agent == "device") {
    t1.start();
    on (Locales[0]:LocaleModel).GPU do {
      t2.start();
      forall i in rows {
	for j in cols {
	  B[i,j] = A[i,j];
	}
      }
      t2.stop();
     }
     t1.stop();
   } 
   else {
     t1.start();
     on (Locales[0]:LocaleModel).CPU do {
       t2.start();
       forall i in rows {
	 for j in cols {
	   B[i,j] = A[i,j];
	 }
       }
       t2.stop();
     }
     t1.stop();
   }

  if (!verify_results(A,B))  {
    writeln("FAIL!");  
  }
  else { 
    writeln("PASS");
  }
}    
    



proc main() {

  t0.start();
  rowmajor(agent);
  t0.stop();


  t3.start();
  colmajor(agent);
  t3.stop();

  if (verbose) then {
    writeln("RMO:\t ", t0.elapsed() * 1000, " ms");
    writeln("CMO:\t ", t3.elapsed() * 1000, " ms");
  }
  else {
    writeln(t1.elapsed() * 1000,",",t3.elapsed() * 1000); 
  }
  t0.clear();
  t1.clear();
  t2.clear();
  t3.clear();

  return 0;
}
