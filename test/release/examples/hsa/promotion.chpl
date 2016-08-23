config var n: int = 64;

var D: domain(1) = {1..n};

var A: [D] int;
var B: [D] int;

//inline
proc square(i: int) : int {
  return i * i;
}

pragma "request gpu offload"
proc run() {
  on (Locales[0]:LocaleModel).GPU do {
    [i in D] A(i) = i;
    B = square(A);
  }
  writeln("A is: ", A);
  writeln("B is: ", B);
}

run();
