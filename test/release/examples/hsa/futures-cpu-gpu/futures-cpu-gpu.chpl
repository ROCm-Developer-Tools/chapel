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

use Futures;

/*
 * This example creates a sample DAG
 *            A_cpu  A_gpu
 *              \     /
 *               B_cpu
 *                 |
 *               C_gpu
 *
 *
 * A: x*2
 * B: x1+x2
 * C: x*4
 */
config const X = 1;

// launch A on GPU
const A_gpu = async("test_A", int, X);

// launch A on CPU
const A_cpu = async(lambda(x: int) { return x * 2; }, X);

// launch B on CPU, but only after both A_cpu and A_gpu complete 
const B_cpu = (A_cpu, A_gpu).andThen(lambda(x: (int, int)) {return x(1) + x(2); } );

// launch C on GPU but only after B completes
const C_gpu = B_cpu.andThen("test_C", int);

writeln(C_gpu.get());
