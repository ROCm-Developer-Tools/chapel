
use Time;

var t:Timer;

config var COUNT = 16;
var A: [1..COUNT] int(32);
for a in A {
  a = 10;
}

var sum: int(32) = 0;
on (Locales[0]:LocaleModel).GPU do {
  t.start();
  sum =  + reduce A;
  t.stop();
}

writeln("Result is ", sum);
writeln("Time in sec msec ", t.elapsed() * 1000.00);
