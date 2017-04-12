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
config const numTasks = 1;

var D: domain(1) = {1..n};

var A: [D] int;
var B: [D] int;

iter count(n: int, low: int=1) {
  for i in low..#n do
    yield i;
}

proc computeChunk(r: range, myChunk, numChunks) where r.stridable == false {
  const numElems = r.length;
  const elemsPerChunk = numElems/numChunks;
  const mylow = r.low + elemsPerChunk*myChunk;
  if (myChunk != numChunks - 1) {
    return mylow..#elemsPerChunk;
  } else {
    return mylow..r.high;
  }
}

iter count(param tag: iterKind, n: int, low: int=1)
       where tag == iterKind.leader {
  coforall tid in 0..#numTasks {
    const myIters = computeChunk(low..#n, tid, numTasks);
    const zeroBasedIters = myIters.translate(-low);
    yield (zeroBasedIters,);
  }
}

iter count(param tag: iterKind, n: int, low: int=1, followThis)
       where tag == iterKind.follower && followThis.size == 1 {
  const lowBasedIters = followThis(1).translate(low);
  for i in lowBasedIters do
    yield i;
}

pragma "request gpu offload"
proc run() {
  on (Locales[0]:LocaleModel).GPU do {
    [i in D] A(i) = i;

    forall (aa,bb) in zip(A,B) do
      bb = -aa;
  }
  writeln("A is: ", A);
  writeln("B is: ", B);
  on (Locales[0]:LocaleModel).GPU do {
    forall (i, a) in zip(count(n), A) do
      a = i * i;
  }
  writeln("A is: ", A);
}

run();
