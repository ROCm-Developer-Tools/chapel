__kernel void test_A(int x, __global int *ret) {
    *ret = 2 * x;
}

__kernel void test_B(int x, __global int *ret) {
    *ret = 3 * x;
}

__kernel void test_C(int x, __global int *ret) {
    *ret = 4 * x;
}
