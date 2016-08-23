
var A: [1..64] int;
var xxx = 15;

pragma "request gpu offload"
proc run() {
  on (Locales[0]:LocaleModel).GPU do {
    forall a in A {
      a = xxx;
    }
  }

  writeln("A is:\n", A);
}
run();
