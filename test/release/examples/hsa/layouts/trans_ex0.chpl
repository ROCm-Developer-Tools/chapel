/**
 * Example showing the use of transposed layout. 
 * 
 * To validate results, build program as follows
 *    chpl -o trans --set chpl_dl_validate=true trans_ex0.chpl
 *
 * This will produce the following output for the transformed array. 
 * 
 *    (original index) (transposed index) [linear index] value 
 */ 

use LayoutTranspose;

var rows = 1..4;
var cols = 1..8;

var domRMO : domain(2) = {rows, cols};
var domCMO : domain(2) dmapped Transpose() = {rows, cols};

var A : [domRMO] real; 
var B : [domCMO] real; 

var numrows = 4;
var numcols = 8;

/* initialize elements with value of linear index in RMO */ 
for i in rows {
  for j in cols {
    A[i, j] = (i - 1) * numcols + j;
    B[i, j] = (i - 1) * numcols + j;
  }
}

// print the two arrays. should be identical
writeln("Original array");
writeln(A);
writeln("Transposed array");
writeln(B);
