
use Random;

config var COUNT = 5000000;
config var NUM_ITER = 10;

// The randomly generted count is used both as array size and array element
// value
proc run_reduce(count: int) {
  writeln("Running reduction on ", count, " items");
  var A: [1..count] int;
  for a in A {
    a = count;
  }

  var sum: int = 0;
  on (Locales[0]:LocaleModel) do {
    sum =  + reduce A;
  }
  assert(sum == count * count);
}

var rnd = new RandomStream();
for i in 1..NUM_ITER {
  run_reduce(1 + (COUNT * rnd.getNext()):int);
}
