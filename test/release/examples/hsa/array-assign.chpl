config var n: int = 64;

var D: domain(1) = {1..n};

var A: [D] int;
var B: [D] int;

pragma "request gpu offload"
proc run() {
  on (Locales[0]:LocaleModel).GPU do {
    [i in D] A(i) = i + 11789;

    B = -A + 11789;
  }
  writeln("B is: ", B);

  on (Locales[0]:LocaleModel).GPU do {
    B = -B;
  }
  writeln("B is: ", B);
}

run();
