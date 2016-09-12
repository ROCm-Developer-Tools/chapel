
pragma "request gpu offload"
proc run() {
  var A: [1..100] int;
  on (Locales[0]:LocaleModel).GPU do {
    [i in 1..A.numElements] if i % 2 == 1 then A[i] = i;
  }
  writeln("A is:\n", A);
}

run();
