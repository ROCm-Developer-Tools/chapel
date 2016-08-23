
/*proc sum_all(i: int) : int {
  if (i <= 1) {
    return i;
  }
  return sum_all(i - 1) + i;
}*/

proc nest_two(i: int) : int {
  return i + 2;
}

proc nest_one(i: int) : int {
  if (i == 0) {
    return i;
  }
  return nest_two(i - 1) + i;
}

pragma "request gpu offload"
proc run() {
  var A: [1..8] int;
  on (Locales[0]:LocaleModel).GPU do {
    forall i in 1..8 {
      A[i] = nest_one(i);
    }
  }
  writeln("A is:\n", A);
}

run();
