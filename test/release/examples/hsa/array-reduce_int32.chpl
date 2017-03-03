
use Random;

config var COUNT = 50000;
config var PROD_COUNT = 30;
config var NUM_ITER = 10;

// The randomly generted count is used both as array size and array element
// value
proc sum_reduce(count: int(32)) {
  writeln("Running sum reduction on ", count, " items");
  var A: [1..count] int(32);
  for a in A {
    a = count;
  }

  var sum: int(32) = 0;
  writeln(" starting ..");
  on (Locales[0]:LocaleModel).GPU do {
    sum =  + reduce A;
  }
  writeln("sum is ", sum);
  assert(sum == count * count);
}

proc prod_reduce(count: int(32)) {
  writeln("Running product reduction on ", count, " items");
  var A: [1..count] int(32);
  for a in A {
    a = 2;
  }

  var prod: int(32) = 0;
  writeln(" starting ..");
  on (Locales[0]:LocaleModel).GPU do {
    prod =  * reduce A;
  }
  writeln("prod is ", prod);
  assert(prod == 2 ** count);
}

proc max_reduce(count: int(32)) {
  writeln("Running max reduction on ", count, " items");
  var A: [1..count] int(32);
  var i: int(32) = 1;
  for a in A {
    a = i;
    i += 1;
  }

  var max: int(32) = 0;
  writeln(" starting ..");
  on (Locales[0]:LocaleModel).GPU do {
    max =  max reduce A;
  }
  writeln("max is ", max);
  assert(max == count);
}

proc min_reduce(count: int(32)) {
  writeln("Running min reduction on ", count, " items");
  var A: [1..count] int(32);
  var i: int(32) = 1;
  for a in A {
    a = i;
    i += 1;
  }

  var minimum: int(32) = 0;
  writeln(" starting ..");
  on (Locales[0]:LocaleModel).GPU do {
    minimum =  min reduce A;
  }
  writeln("min is ", minimum);
  assert(minimum == 1);
}

var rnd = new RandomStream();
for i in 1..NUM_ITER {
  sum_reduce(1 + (COUNT * rnd.getNext()):int(32));
  //sum_reduce(4096);
}
for i in 1..NUM_ITER {
  prod_reduce(1 + (PROD_COUNT * rnd.getNext()):int(32));
}

for i in 1..NUM_ITER {
  max_reduce(1 + (COUNT * rnd.getNext()):int(32));
}

for i in 1..NUM_ITER {
  min_reduce(1 + (COUNT * rnd.getNext()):int(32));
}
