
#define WKGRP_SIZE 64
#define SEQ_CHUNK_SIZE 16

enum ReduceOp {
  SUM,
  PROD,
  LOGICAL_AND,
  LOGICAL_OR,
  BIT_AND,
  BIT_OR,
  BIT_XOR,
  MIN,
  MAX,
};
