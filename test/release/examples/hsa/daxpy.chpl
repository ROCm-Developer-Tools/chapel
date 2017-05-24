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

use Time;

config const m = 100;
config const n = 10000;


pragma "request gpu offload"
proc runGPU() {
  var x: [1..n] int;
  var y: [1..n] int;
  var a: int;
  a=3;

for i in 1..n {
 x[i]=i;
 y[i]=i*i+i;
}

  var t:Timer;
  t.start();
  on (Locales[0]:LocaleModel).GPU do {
    for i in 1..m {
      forall i in 1..n {
        y[i] = y[i] + a * x[i];
      }
    }
  }
  t.stop();
  writeln("runGPU elapsed ", t.elapsed()/m);
 // writeln("A is:\n", y);
}
proc runCPU() {
  var y: [1..n] int;
  var x: [1..n] int;
  var a: int;
  a=3;
 
for i in 1..n {
 x[i]=i;
 y[i]=i*i+i;
}
 

  var t:Timer;
  t.start();
  for i in 1..m {
    forall i in 1..n {
      y[i] = y[i]+ a*x[i];
    }
  }
  t.stop();
  writeln("runCPU elapsed ", t.elapsed()/m);
 // writeln("A is:\n", y);
}

// Uncommenting this line makes it core dump.
runGPU();
runCPU();
