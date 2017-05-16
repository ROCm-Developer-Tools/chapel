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

use Random;
use Time;

config var COUNT = 500000;
config var PROD_COUNT = 32;
config var NUM_ITER = 10;

// The randomly generted count is used both as array size and array element
// value
proc sum_reduce(count: int) {
  writeln("Running sum reduction on ", count, " items");
  var A: [1..count] int;
  for a in A {
    a = count;
  }

  var sum: int = 0;
  writeln(" starting GPU ..");
  const gpu_startTime = getCurrentTime();
  on (Locales[0]:LocaleModel).GPU do {
    sum =  + reduce A;
  }
  const gpu_stopTime = getCurrentTime();
  const gpu_elapsed = gpu_stopTime - gpu_startTime; 
  writeln("*****GPU time is:", gpu_elapsed, "sum = ", sum);
  assert(sum == count * count);
 
  for a in A {
    a = count;
  }

  sum = 0;
  writeln(" starting CPU..");
  const cpu_startTime = getCurrentTime();
  on (Locales[0]:LocaleModel) do {
    sum =  + reduce A;
  }
  const cpu_stopTime = getCurrentTime();
  const cpu_elapsed = cpu_stopTime - cpu_startTime; 
  writeln("------ CPU time is ", cpu_elapsed, "sum = ", sum);
  assert(sum == count * count);


}

proc prod_reduce(count: int) {
  writeln("Running product reduction on ", count, " items");
  var A: [1..count] int;
  for a in A {
    a = 2;
  }

  var prod: int = 0;
  writeln(" starting GPU ..");
  const gpu_startTime = getCurrentTime();
  on (Locales[0]:LocaleModel).GPU do {
    prod =  * reduce A;
  }
  const gpu_stopTime = getCurrentTime();
  const gpu_elapsed = gpu_stopTime - gpu_startTime;
  writeln("*****GPU time is:", gpu_elapsed, "prod = ", prod);
  assert(prod == 2 ** count);

  for a in A {
    a = 2;
  }

  prod = 0;
  writeln(" starting CPU ..");
  const cpu_startTime = getCurrentTime();
  on (Locales[0]:LocaleModel) do {
    prod =  * reduce A;
  }
  const cpu_stopTime = getCurrentTime();
  const cpu_elapsed = cpu_stopTime - cpu_startTime;
  writeln(" ----- CPU time is:", cpu_elapsed, "prod = ", prod);
  assert(prod == 2 ** count);


}

proc max_reduce(count: int) {
  writeln("Running max reduction on ", count, " items");
  var A: [1..count] int;
  var i: int = 1;
  for a in A {
    a = i;
    i += 1;
  }

  var max: int = 0;
  writeln(" starting GPU..");
  const gpu_startTime = getCurrentTime();
  on (Locales[0]:LocaleModel).GPU do {
    max =  max reduce A;
  }
  const gpu_stopTime = getCurrentTime();
  const gpu_elapsed = gpu_stopTime - gpu_startTime;
  writeln("*****GPU time is:", gpu_elapsed, "max = ", max);
  assert(max == count);
   
   i =1;
   for a in A {
    a = i;
    i += 1;
  }

  max = 0;
  writeln(" starting CPU..");
  const cpu_startTime = getCurrentTime();
  on (Locales[0]:LocaleModel) do {
    max =  max reduce A;
  }
  const cpu_stopTime = getCurrentTime();
  const cpu_elapsed = cpu_stopTime - cpu_startTime;
  writeln("-------CPU time is:", cpu_elapsed, "max = ", max);
  assert(max == count);

}

proc min_reduce(count: int) {
  writeln("Running min reduction on ", count, " items");
  var A: [1..count] int;
  var i: int = 1;
  for a in A {
    a = i;
    i += 1;
  }

  var minimum: int = 0;
  writeln(" starting GPU..");
  const gpu_startTime = getCurrentTime();
  on (Locales[0]:LocaleModel).GPU do {
    minimum =  min reduce A;
  }
  const gpu_stopTime = getCurrentTime();
  const gpu_elapsed = gpu_stopTime - gpu_startTime;
  writeln("*****GPU time is:", gpu_elapsed, "min = ", minimum);
  assert(minimum == 1);
   
   i = 1;
   for a in A {
    a = i;
    i += 1;
  }

  minimum = 0;
  writeln(" starting CPU..");
  const cpu_startTime = getCurrentTime();
  on (Locales[0]:LocaleModel) do {
    minimum =  min reduce A;
  }
  const cpu_stopTime = getCurrentTime();
  const cpu_elapsed = cpu_stopTime - cpu_startTime;
  writeln("-------CPU time is:", cpu_elapsed, "min = ", minimum);
  assert(minimum == 1);


}

var rnd = new RandomStream();
for i in 1..NUM_ITER {
  sum_reduce(1 + (COUNT * rnd.getNext()):int);
}

for i in 1..NUM_ITER {
  prod_reduce(1 + (PROD_COUNT * rnd.getNext()):int);
}

for i in 1..NUM_ITER {
  max_reduce(1 + (COUNT * rnd.getNext()):int);
}

for i in 1..NUM_ITER {
  min_reduce(1 + (COUNT * rnd.getNext()):int);
}
