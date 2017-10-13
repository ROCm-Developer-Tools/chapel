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

config param GPU = false;
config const tileWidth = 2;
config const tileHeight = 2;

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

  var A_str = "ACACACTA";
  var B_str = "AGCACACA";
  var A = getIntArrayFromString(A_str);
  var B = getIntArrayFromString(B_str);
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
  //const distrDom = distrSpace;

  var aDistr: [distrDom] [1..(A.numElements)] int(8);
  var bDistr: [distrDom] [1..(B.numElements)] int(8);
  //var aDistr: [1..(A.numElements)] int(8);
  //var bDistr: [1..(B.numElements)] int(8);

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
  const tile_0_2d_domain = {0..tileHeight, 0..tileWidth};
  const tile_1_2d_domain = {1..tileHeight, 1..tileWidth};
  const tileHeight_1_domain = {1..tileHeight};
  const tileWidth_1_domain = {1..tileWidth};

  // sort the tm_1_2d_domain to a diagonal-major ordering
  var diagDomain: domain((int, int));
  for (i, j) in tm_1_2d_domain {
    diagDomain += (i, j);
  }

  for (i, j) in diagDomain.sorted(diagonalMajorComparator) {
    var i1 = i;
    var j1 = j;
    var diag_id = i + j;
    var min_diag_id = 2;
    var max_diag_id = tmHeight + tmWidth;

    if (diag_id > min_diag_id && diag_id < max_diag_id) {
      // execute on GPU
      writeln("Tile (", i1, ", ", j1, ") on GPU");
      tileMatrix(i1, j1) = (
          tileMatrix(i1 - 0, j1 - 1), 
          tileMatrix(i1 - 1, j1 - 0),
          tileMatrix(i1 - 1, j1 - 1)
          ).andThen_args("compute_tile", Tile, 
            c_ptrTo(tiles(i1, j1)),
            A_carray, B_carray);
    } else {
      // execute on CPU
      writeln("Tile (", i1, ", ", j1, ") on CPU");
      tileMatrix(i1, j1) = (
          tileMatrix(i1 - 0, j1 - 1), 
          tileMatrix(i1 - 1, j1 - 0),
          tileMatrix(i1 - 1, j1 - 1)
          ).andThen(lambda(depTiles: (Tile, Tile, Tile), tile: Tile, A_carray: c_ptr(int(8)), B_carray: c_ptr(int(8)))
            {
            // retrieve dependent tiles
            //var left  = tileMatrix(i1 - 0, j1 - 1).get();
            //var above = tileMatrix(i1 - 1, j1 - 0).get();
            //var diag  = tileMatrix(i1 - 1, j1 - 1).get();
            var left  = depTiles(1);
            var above = depTiles(2);
            var diag  = depTiles(3);
            var i1 = tile.i;
            var j1 = tile.j;
            var tileHeight = tile.tileHeight;
            var tileWidth = tile.tileWidth;

            const tile_0_2d_domain = {0..tileHeight, 0..tileWidth};
            const tile_1_2d_domain = {1..tileHeight, 1..tileWidth};
            const tileHeight_1_domain = {1..tileHeight};
            const tileWidth_1_domain = {1..tileWidth};

            //var tile = createTile();

            // perform computation
            var localMatrix: [tile_0_2d_domain] int;

            for i2 in tileHeight_1_domain do localMatrix(i2, 0)  = rightColumn(left, i2 - 1);
            for j2 in tileWidth_1_domain do localMatrix(0 , j2) = bottomRow(above, j2 - 1);
            localMatrix(0, 0) = diagonal(diag);

            for (ii, jj) in tile_1_2d_domain do {
              var aIndex = ((j1 - 1) * tileWidth) + jj;
              var bIndex = ((i1 - 1) * tileHeight) + ii;

              var aElement = A_carray(aIndex);
              var bElement = B_carray(bIndex);

              var diagScore = localMatrix(ii - 1, jj - 1) + alignmentScoreMatrix(bElement, aElement);
              var leftScore = localMatrix(ii - 0, jj - 1) + alignmentScoreMatrix(aElement, 0);
              var topScore  = localMatrix(ii - 1, jj - 0) + alignmentScoreMatrix(0,        bElement);

              localMatrix(ii, jj) = max(diagScore, leftScore, topScore);
            } // end of for

            for idx in tileHeight_1_domain do rightColumn(tile, idx - 1) = localMatrix(idx   , tileWidth);
            for idx in tileWidth_1_domain do bottomRow(tile, idx - 1)   = localMatrix(tileHeight, idx  );

            return tile;
            }, tiles(i1, j1), A_carray, B_carray);
    }
  } 

  var score = bottomRow(tileMatrix(tmHeight, tmWidth).get(), tileWidth-1);

  const execTimeComp = getCurrentTime() - startTimeComp;
  writeln("Main: The score is ", score);
  writeln("Main: Execution time ", execTimeComp, " seconds.");

  writeln("Main: ends.");
  return 0;
}

