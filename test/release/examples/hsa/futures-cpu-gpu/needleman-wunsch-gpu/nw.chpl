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
use Sort;
use IO;
use Futures;
use CyclicDist;
use BlockCycDist;
use Atomics;
use Random;

config const tileWidth = 32;
config const tileHeight = 32;
config const seqSize = 256;

pragma "no ref"
extern record ArrayData {
  //var down: [0..#tileWidth] int;
  //var right: [0..#tileHeight] int;
  var down: c_ptr(int(64));
  var right: c_ptr(int(64));
}

pragma "no ref"
extern record Tile {
  var ad: ArrayData;
  var i: int(64);
  var j: int(64);
  var tileHeight: int(64);
  var tileWidth: int(64);
}

proc bottomRow(t: Tile, idx: int) ref {
  return t.ad.down[idx];
}

proc rightColumn(t: Tile, idx: int) ref {
  return t.ad.right[idx];
}

proc diagonal(t: Tile) ref {
  return t.ad.down[tileWidth - 1];
}

proc createTile(i, j) : Tile {
  var t = new Tile();
  t.ad.down = c_malloc(int, tileWidth);
  t.ad.right = c_malloc(int, tileHeight);
  t.i = i;
  t.j = j;
  t.tileHeight = tileHeight;
  t.tileWidth = tileWidth;
  return t;
}

proc isSupported(inputChar: string): bool {
  var toBeReturned = false;
  select inputChar {
    when "A" do toBeReturned = true;
    when "C" do toBeReturned = true;
    when "G" do toBeReturned = true;
    when "T" do toBeReturned = true;
  }
  return toBeReturned;
}

proc charMap(inputChar: string, idx: int): int(8) {
  var toBeReturned: int(8) = -1;
  select inputChar {
    when "_" do toBeReturned = 0;
    when "A" do toBeReturned = 1;
    when "C" do toBeReturned = 2;
    when "G" do toBeReturned = 3;
    when "T" do toBeReturned = 4;
  }
  if (toBeReturned == -1) {
    halt("Unsupported character in at index ", idx, " for input: ", inputChar);
  } else {
    // writeln(inputChar, " maps to ", toBeReturned);
  }
  return toBeReturned;
}

proc printMatrix(array: [] real): void {
  writeln(array);
}

//extern var alignmentScoreMatrix: [0..#5, 0..#5] int;
var alignmentScoreMatrix: [0..#5, 0..#5] int = (
      ( -1, -1, -1, -1, -1),
      ( -1,  2, -4, -2, -4),
      ( -1, -4,  2, -4, -2),
      ( -1, -2, -4,  2, -4),
      ( -1, -4, -2, -4,  2));

proc createRandomDNASequence(arr: [?D] ?eltType) {
  //fillRandom(arr);
  fillRandomWithBounds(arr, 1, 4);
}


proc getIntArrayFromString(line: string) {
  // initially store the results in an associative domain
  var myDom: domain(int);
  var myArray: [myDom] int(8);
  var myArraySize = 1;

  {
    var lineLength = line.length;
    for i in {1..#(lineLength)} do {
      var loopChar = line(i);
      myDom += myArraySize;
      myArray(myArraySize) = charMap(loopChar, i);
      myArraySize = myArraySize + 1;
    }
  }

  var resDom: domain(1) = {1..#(myArraySize - 1)};
  var resArray: [resDom] int(8);
  for i in myDom do resArray(i) = myArray(i);

  return resArray;
}

proc getCArrayFromChplArray(A) : c_ptr(int(8)) {
  type t = A._instance.eltType;
  var A_array: c_ptr(int(8)) = c_malloc(int(8), A.numElements);
  
  for i in 0..A.numElements-1 do {
    A_array(i) = A(i+1);
    //writeln("A[", i, "] = ", A_array(i));
  }
  return A_array;
}

config const X = 1;

extern var alignmentScoreMatrixGPU: c_ptr(int);; 
//var A = getIntArrayFromString("ACACACTA");
//var B = getIntArrayFromString("AGCACACA");

proc main(): int {

  writeln("Main: PARALLEL starts...");

  //var A_str = "ACACACTA";
  //var B_str = "AGCACACA";
  //var A = getIntArrayFromString(A_str);
  //var B = getIntArrayFromString(B_str);
  var A: [{1..seqSize}] int(8);
  var B: [{1..seqSize}] int(8);
  createRandomDNASequence(A);
  createRandomDNASequence(B);
  var A_carray: c_ptr(int(8)) = getCArrayFromChplArray(A);
  var B_carray: c_ptr(int(8)) = getCArrayFromChplArray(B);

  var tmWidth = A.numElements / tileWidth;
  var tmHeight = B.numElements / tileHeight;

  writeln("Main: Configuration Summary");
  writeln("  numLocales = ", numLocales);
  writeln("  tileHeight = ", tileHeight);
  writeln("    B.length = ", B.numElements);
  writeln("    tmHeight = ", tmHeight);
  writeln("  tileWidth = ", tileWidth);
  writeln("    A.length = ", A.numElements);
  writeln("    tmWidth = ", tmWidth);
  stdout.flush();

  writeln("Main: initializing copies of A and B"); stdout.flush();
  const startTimeCopies = getCurrentTime();

  const distrSpace = {0..(numLocales - 1)};
  const distrDom: domain(1) dmapped Cyclic(startIdx=distrSpace.low) = distrSpace;

  var aDistr: [distrDom] [1..(A.numElements)] int(8);
  var bDistr: [distrDom] [1..(B.numElements)] int(8);

  [i in distrSpace] on Locales(i) do {
    writeln("Main: initializing data on locale-", i); stdout.flush();
    for j in {1..(A.numElements)} do aDistr(i)(j) = A(j);
    for j in {1..(B.numElements)} do bDistr(i)(j) = B(j);
  }

  const endTimeCopies = getCurrentTime();
  writeln("Main: initialized copies of A and B in ", (endTimeCopies - startTimeCopies), " seconds."); stdout.flush();

  const startTimeAlloc = getCurrentTime();

  var unmapped_tile_matrix_space = {0..tmHeight, 0..tmWidth};
  var mapped_tile_matrix_space = unmapped_tile_matrix_space dmapped Cyclic(startIdx=unmapped_tile_matrix_space.low);
  //var tileMatrix: [unmapped_tile_matrix_space] Future(Tile);
  var tileMatrix: [mapped_tile_matrix_space] Future(Tile);
  var tiles: [mapped_tile_matrix_space] Tile;
  for (i, j) in mapped_tile_matrix_space do {
    tiles(i, j) = createTile(i, j);
  }

  const endTimeAlloc = getCurrentTime();
  writeln("Main: allocated tiles in ", (endTimeAlloc - startTimeAlloc), " seconds."); stdout.flush();

  const startTimeRow = getCurrentTime();

  var t = tiles(0, 0); //createTile();
  var i = 0;
  for j in 0..#tileWidth do {
    bottomRow(t, j) = -1 * ((i - 1) * tileWidth + j + 1);
  }
  for j in 0..#tileHeight do {
    rightColumn(t, j) = -1 * ((i - 1) * tileHeight + j + 1); 
  }
  tileMatrix(0, 0).set(t);

  for i in 1..tmWidth do {
    var t = tiles(0, i);//createTile();
    for j in 0..#tileWidth do {
      bottomRow(t, j) = -1 * ((i - 1) * tileWidth + j + 1);
    }
    tileMatrix(0, i).set(t);
  }
  const endTimeRow = getCurrentTime();
  writeln("Main: initialized rows in ", (endTimeRow - startTimeRow), " seconds."); stdout.flush();

  const startTimeCol = getCurrentTime();
  for i in 1..tmHeight do
    {
      var t = tiles(i, 0); //createTile();
      for j in 0..#tileHeight do {
        rightColumn(t, j) = -1 * ((i - 1) * tileHeight + j + 1); 
      }
      for j in 0..#tileWidth do {
        bottomRow(t, j) = -1 * ((i - 1) * tileWidth + j + 1);
      }
      tileMatrix(i, 0).set(t);
    }
    const endTimeCol = getCurrentTime();
    writeln("Main: initialized columns in ", (endTimeCol - startTimeCol), " seconds."); stdout.flush();


    writeln("Main: starting computation..."); stdout.flush();
    const startTimeComp = getCurrentTime();

    const tm_1_2d_domain = {1..tmHeight, 1..tmWidth};

    // sort the tm_1_2d_domain to a diagonal-major ordering
    var diagDomain: domain((int, int));
    for (i, j) in tm_1_2d_domain {
      diagDomain += (i, j);
    }

    for (i, j) in diagDomain.sorted(diagonalMajorComparator) {
      var i1 = i;
      var j1 = j;

      tileMatrix(i1, j1) = (
          tileMatrix(i1 - 0, j1 - 1), 
          tileMatrix(i1 - 1, j1 - 0),
          tileMatrix(i1 - 1, j1 - 1)
          ).andThen_args("compute_tile", Tile, 
            c_ptrTo(tiles(i1, j1)),
            A_carray, B_carray);
    } 

    var score = bottomRow(tileMatrix(tmHeight, tmWidth).get(), tileWidth-1);

    const execTimeComp = getCurrentTime() - startTimeComp;
    writeln("Main: The score is ", score);
    writeln("Main: Execution time ", execTimeComp, " seconds.");

    writeln("Main: ends.");
    return 0;
  }

