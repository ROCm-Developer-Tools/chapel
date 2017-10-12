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

__kernel void compute_tile(
        __global long int *down,
        __global long int *right,
        long int i1,
        long int j1,
        long int tileHeight,
        long int tileWidth,
        __global char *aDistrLoc,
        __global char *bDistrLoc,
        __global long int *left_right,
        __global long int *above_down,
        long int inital_diag_val
        ) {
    __local long int localMatrix[tile_size+1][tile_size+1];//tileHeight][tileWidth];
    for (int ii = 0; ii <= tile_size; ii++) {
        for (int jj = 0; jj <= tileWidth; jj++) {
            localMatrix[ii][jj] = 0;
        }
    }
    for (int idx = 1; idx <= tileHeight; idx++) {
        localMatrix[idx][0] = left_right[idx - 1];
    }
    for (int idx = 1; idx <= tileWidth; idx++) {
        localMatrix[0][idx] = above_down[idx - 1];
    }
    localMatrix[0][0] = inital_diag_val;

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
        right[idx - 1] = localMatrix[idx][tileWidth];
    }
    for (int idx = 1; idx <= tileWidth; idx++) {
        down[idx - 1]   = localMatrix[tileHeight][idx];
    }
}

