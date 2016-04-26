var A: [1..16] int;
var numChunks = 4;
on (Locales[0]:LocaleModel).GPU do {
  coforall wid in 1..#numChunks {
    const lo = 1 + (wid - 1) *  4;
    const hi = lo + 3;
    //writeln("wid, lo, hi, is ", wid, " ", lo, " ",  hi);
    for i in lo..hi {
      A[i] = i;
    }
  }
}

writeln("A is:\n", A);

