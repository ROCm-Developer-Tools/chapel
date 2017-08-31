use Futures;

config const X = 1;

const A = async("test_A", int, X);
const B = async(lambda(x: int) { return x * 3; }, X);
const C = async("test_C", int, X);

const D = async("test_A", int, X)
          .andThen("test_B", int)
          .andThen("test_C", int)
          .andThen(lambda(x: int) { return x+1; });

const F = (A, B, C, D).andThen(lambda(x: (int, int, int, int)) {return x(1) + x(2) + x(3) + x(4); } );
writeln(F.get());
