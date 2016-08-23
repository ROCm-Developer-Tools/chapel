pragma "request gpu offload"
proc run() {
  var A: [1..100] int;
  on (Locales[0]:LocaleModel).GPU do {
    forall i in 1..100 by -2 {
      A[i] = i + 1164;
    }
  }
  writeln("A is:\n", A);
}

/*pragma "request gpu offload"
proc run() {
  var A: [1..100] int;
  on (Locales[0]:LocaleModel).GPU do {
    forall i in 1..100 by 2 {
      A[i] = i + 1164;
    }
  }
  writeln("A is:\n", A);
}*/

run();
