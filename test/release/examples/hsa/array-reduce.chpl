
use Time;

var t1, t2:Timer;

config var COUNT = 16;
var A: [1..COUNT] int(32);
for a in A {
  a = 10;
}

var sum: int(32) = 0;
on (Locales[0]:LocaleModel).GPU do {
  t1.start();
  sum =  + reduce A;
  t1.stop();
}
writeln("Result is ", sum);
writeln("Time in msec for GPU execution ", t1.elapsed() * 1000.00);

/*sum = 0;
on (Locales[0]:LocaleModel).CPU do {
  t2.start();
  sum =  + reduce A;
  t2.stop();
}
writeln("Result is ", sum);
writeln("Time in msec for CPU execution ", t2.elapsed() * 1000.00);
*/
