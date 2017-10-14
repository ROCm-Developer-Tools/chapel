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

class ArrayData {
  var down: [0..#tileWidth] int;
  var right: [0..#tileHeight] int;

  proc bottomRow(idx: int) ref {
    return down(idx);
  }

  proc rightColumn(idx: int) ref {
    return right(idx);
  }

}

class Tile {

  var border: bool;
  var ad: ArrayData;

  proc Tile() {
    this.ad = new ArrayData();
  }

  proc setBorder(): void {
    this.border = true;
  }

  proc bottomRow(idx: int) ref {
    return ad.bottomRow(idx);
  }

  proc rightColumn(idx: int) ref {
    return ad.rightColumn(idx);
  }

  proc diagonal() ref {
    return ad.bottomRow(tileWidth - 1);
  }
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

const alignmentScoreMatrix: [0..#5, 0..#5] int = (
      ( -1, -1, -1, -1, -1),
      ( -1,  2, -4, -2, -4),
      ( -1, -4,  2, -4, -2),
      ( -1, -2, -4,  2, -4),
      ( -1, -4, -2, -4,  2));

proc createRandomDNASequence(arr: [?D] ?eltType) {
  //fillRandom(arr);
  fillRandomWithBounds(arr, 1, 4);
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

config const X = 1;

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
  //const distrDom = distrSpace;

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

  const endTimeAlloc = getCurrentTime();
  writeln("Main: allocated tiles in ", (endTimeAlloc - startTimeAlloc), " seconds."); stdout.flush();

  const startTimeRow = getCurrentTime();

  var t = new Tile();
  var i = 0;
  for j in 0..#tileWidth do {
    t.bottomRow(j) = -1 * ((i - 1) * tileWidth + j + 1);
  }
  for j in 0..#tileHeight do {
    t.rightColumn(j) = -1 * ((i - 1) * tileHeight + j + 1); 
  }
  tileMatrix(0, 0).set(t);

  for i in 1..tmWidth do {
    var t = new Tile();
    for j in 0..#tileWidth do {
      t.bottomRow(j) = -1 * ((i - 1) * tileWidth + j + 1);
    }
    tileMatrix(0, i).set(t);
  }
  const endTimeRow = getCurrentTime();
  writeln("Main: initialized rows in ", (endTimeRow - startTimeRow), " seconds."); stdout.flush();

  const startTimeCol = getCurrentTime();
  for i in 1..tmHeight do
    {
      var t = new Tile();
      for j in 0..#tileHeight do {
        t.rightColumn(j) = -1 * ((i - 1) * tileHeight + j + 1); 
      }
      for j in 0..#tileWidth do {
        t.bottomRow(j) = -1 * ((i - 1) * tileWidth + j + 1);
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

      //on tileMatrix(i1, j1).locale do 
      {

        /*if (i1 == 0 || j1 == 0) {
          writeln("In the fringe tiles ", i1, ", ", j1);
          tileMatrix(i1, j1) = async(lambda(x1: int, y1: int) {
          var tile = new Tile();
        //var tile: Tile;

        if (x1 == 0) {
        for k in 0..#tileWidth {
        //[k in 0..#tileWidth] 
        tile.bottomRow(k) = -1 * ((y1 - 1) * tileWidth + k + 1); 
        //tile.setBottomRow(k, -1 * ((y1 - 1) * tileWidth + k + 1)); 
        writeln("(", x1, ", ", y1, ", ", k, ") = ", -1 * ((y1 - 1) * tileWidth + k + 1)); 
        }
        }
        if (y1 == 0) {
        for k in 0..#tileHeight {
        //[k in 0..#tileHeight] 
        //tile.setRightColumn(k, -1 * ((x1 - 1) * tileHeight + k + 1));
        tile.rightColumn(k) = -1 * ((x1 - 1) * tileHeight + k + 1);
        writeln("(", x1, ", ", y1, ", ", k, ") = ", -1 * ((x1 - 1) * tileHeight + k + 1)); 
        }
        }
        return tile;
        }, i1, j1);
        //var tmp = tileMatrix(i1, j1).get();
        //writeln("Tile[", i1, ", ", j1, "]: ", tmp);
        }
        */
        //if (i1 > 0 && j1 > 0) 
        {
          tileMatrix(i1, j1) = (
              tileMatrix(i1 - 0, j1 - 1), 
              tileMatrix(i1 - 1, j1 - 0),
              tileMatrix(i1 - 1, j1 - 1)
              ).andThen(lambda(depTiles: (Tile, Tile, Tile), i1: int, j1: int,
                tmHeight: int, tmWidth: int, tileHeight: int, tileWidth: int,
                A_carray: c_ptr(int(8)), B_carray: c_ptr(int(8))) {
                const tm_1_2d_domain = {1..tmHeight, 1..tmWidth};
                const tile_0_2d_domain = {0..tileHeight, 0..tileWidth};
                const tile_1_2d_domain = {1..tileHeight, 1..tileWidth};
                const tileHeight_1_domain = {1..tileHeight};
                const tileWidth_1_domain = {1..tileWidth};

                var tile = new Tile();

                // retrieve dependent tiles
                //var left  = tileMatrix(i1 - 0, j1 - 1).get();
                //var above = tileMatrix(i1 - 1, j1 - 0).get();
                //var diag  = tileMatrix(i1 - 1, j1 - 1).get();
                var left  = depTiles(1);
                var above = depTiles(2);
                var diag  = depTiles(3);

                // perform computation
                var localMatrix: [tile_0_2d_domain] int;

                for i2 in tileHeight_1_domain do localMatrix(i2, 0)  = left.rightColumn(i2 - 1);
                for j2 in tileWidth_1_domain do localMatrix(0 , j2) = above.bottomRow(j2 - 1);
                localMatrix(0, 0) = diag.diagonal();

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

                for idx in tileHeight_1_domain do tile.rightColumn(idx - 1) = localMatrix(idx   , tileWidth);
                for idx in tileWidth_1_domain do tile.bottomRow(idx - 1)   = localMatrix(tileHeight, idx  );

                return tile;
              }, i1, j1, tmHeight, tmWidth, tileHeight, tileWidth, A_carray, B_carray);
        }
      }
    } 

    var score = tileMatrix(tmHeight, tmWidth).get().bottomRow(tileWidth-1);

    const execTimeComp = getCurrentTime() - startTimeComp;
    writeln("Main: The score is ", score);
    writeln("Main: Execution time ", execTimeComp, " seconds.");

    writeln("Main: ends.");
    return 0;
  }

