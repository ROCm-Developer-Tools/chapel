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

config var COUNT = 5000000;
config var NUM_ITER = 10;

// The randomly generted count is used both as array size and array element
// value
proc run_reduce(count: int) {
  writeln("Running reduction on ", count, " items");
  var A: [1..count] int;
  for a in A {
    a = count;
  }

  var sum: int = 0;
  on (Locales[0]:LocaleModel) do {
    sum =  + reduce A;
  }
  assert(sum == count * count);
}

var rnd = new RandomStream();
for i in 1..NUM_ITER {
  run_reduce(1 + (COUNT * rnd.getNext()):int);
}
