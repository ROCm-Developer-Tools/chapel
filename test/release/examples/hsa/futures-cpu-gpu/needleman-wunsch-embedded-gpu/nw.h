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

#ifndef __NW_H__
#define __NW_H__
typedef struct _ArrayData {
    long int *down;
    long int *right;
} ArrayData;

typedef struct _Tile {
    ArrayData ad;
} Tile;

const int alignmentScoreMatrixGPU[5][5] = {
      { -1, -1, -1, -1, -1},
      { -1,  2, -4, -2, -4},
      { -1, -4,  2, -4, -2},
      { -1, -2, -4,  2, -4},
      { -1, -4, -2, -4,  2}
};

const long int tile_size = 64; 

#endif // __NW_H__
