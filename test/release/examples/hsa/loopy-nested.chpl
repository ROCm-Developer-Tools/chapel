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

/*proc sum_all(i: int) : int {
  if (i <= 1) {
    return i;
  }
  return sum_all(i - 1) + i;
}*/

proc nest_two(i: int) : int {
  return i + 2;
}

proc nest_one(i: int) : int {
  if (i == 0) {
    return i;
  }
  return nest_two(i - 1) + i;
}

pragma "request gpu offload"
proc run() {
  var A: [1..8] int;
  on (Locales[0]:LocaleModel).GPU do {
    forall i in 1..8 {
      A[i] = nest_one(i);
    }
  }
  writeln("A is:\n", A);
}

run();
