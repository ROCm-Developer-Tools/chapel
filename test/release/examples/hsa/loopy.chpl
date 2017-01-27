pragma "request gpu offload"
proc run() {
  var A: [5..100] int;
  on (Locales[0]:LocaleModel).GPU do {
//    forall i in 5..100 {
//    A[i] = i + 1164;
    forall (x, i) in zip(A, A.domain) {
      x = i + 1164;
    }
  }
  writeln("A is:\n", A);
}

run();
