var A: [1..256] int;
var numChunks = 4;
on (Locales[0]:LocaleModel).GPU do {
  coforall wid in 1..#numChunks {
    const lo = 1 + (wid - 1) *  64;
    const hi = lo + 63;
    //writeln("wid, lo, hi, is ", wid, " ", lo, " ",  hi);
    for i in lo..hi {
      A[i] = i;
    }
  }
}

writeln("A is:\n", A);


/* GPU version
 wkgrpSize = ?
 numWkCount = ?
  __kernel void gputemp(__global void *A) {
      size_t wid = get_group_id(0);
      size_t wsize = get_group_size(0);
      size_t lid = get_local_id(0);
      size_t i = wid * wsize + lid;
      A[i] = i;
    }

*/
