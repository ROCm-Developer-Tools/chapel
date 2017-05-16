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

config var n: int = 64;

var D: domain(1) = {1..n};

var A: [D] int;
var B: [D] int;

pragma "request gpu offload"
proc run() {
  on (Locales[0]:LocaleModel).GPU do {
    [i in D] A(i) = i + 11789;

    B = -A + 11789;
  }
  writeln("B is: ", B);

  on (Locales[0]:LocaleModel).GPU do {
    B = -B;
  }
  writeln("B is: ", B);
}

run();
