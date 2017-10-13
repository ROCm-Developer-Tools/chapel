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

#include "nw.h"

typedef struct tile_tuple_s {
    Tile t1;
    Tile t2;
    Tile t3;
} tile_tuple_t;

__kernel void compute_tile(
        __global tile_tuple_t *depTiles,
        __global Tile *tile,
        __global char *aDistrLoc,
        __global char *bDistrLoc,
        __global Tile *ret_tile
        ) {
    local long int localMatrix[tile_size+1][tile_size+1];//tileHeight][tileWidth];
    Tile *left = &(depTiles->t1);
    Tile *above = &(depTiles->t2);
    Tile *diag = &(depTiles->t3);
    long int i1 = tile->i;
    long int j1 = tile->j;
    long int tileHeight = tile->tileHeight;
    long int tileWidth = tile->tileWidth;
    for (int ii = 0; ii <= tile_size; ii++) {
        for (int jj = 0; jj <= tileWidth; jj++) {
            localMatrix[ii][jj] = 0;
        }
    }
    for (int idx = 1; idx <= tileHeight; idx++) {
        localMatrix[idx][0] = left->ad.right[idx - 1];
    }
    for (int idx = 1; idx <= tileWidth; idx++) {
        localMatrix[0][idx] = above->ad.down[idx - 1];
    }
    localMatrix[0][0] = diag->ad.down[tileWidth - 1];
    work_group_barrier(CLK_GLOBAL_MEM_FENCE, memory_scope_all_svm_devices);

    for (int ii = 1; ii <= tileHeight; ii++) {
        for (int jj = 1; jj <= tileWidth; jj++) {
            int aIndex = ((j1 - 1) * tileWidth) + jj;
            int bIndex = ((i1 - 1) * tileHeight) + ii;

            int aElement = aDistrLoc[aIndex-1];
            int bElement = bDistrLoc[bIndex-1];

            int diagScore = localMatrix[ii - 1][jj - 1] + alignmentScoreMatrixGPU[bElement][aElement];
            int leftScore = localMatrix[ii - 0][jj - 1] + alignmentScoreMatrixGPU[aElement][0];
            int topScore  = localMatrix[ii - 1][jj - 0] + alignmentScoreMatrixGPU[0][bElement];

            localMatrix[ii][jj] = max(diagScore, max(leftScore, topScore));
        } // end of for
    } // end of for
    
    work_group_barrier(CLK_GLOBAL_MEM_FENCE, memory_scope_all_svm_devices);
    for (int idx = 1; idx <= tileHeight; idx++) {
        tile->ad.right[idx - 1] = localMatrix[idx][tileWidth];
    }
    for (int idx = 1; idx <= tileWidth; idx++) {
        tile->ad.down[idx - 1]  = localMatrix[tileHeight][idx];
    }
    work_group_barrier(CLK_GLOBAL_MEM_FENCE, memory_scope_all_svm_devices);
    
    Tile ret;
    ret.ad.down = tile->ad.down;
    ret.ad.right = tile->ad.right;
    *ret_tile = ret;
}

