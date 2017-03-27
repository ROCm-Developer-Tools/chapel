/* 
   Base GPU header for OpenCL code 
   Defines types and classes used by OpenCL
*/

#define CHPL_GEN_CODE

#define CHPL_LOCALEID_T_INIT  {0, 0}

#include "helper_kernels_inc.cl"

typedef int syserr;
typedef void* _nilType;
typedef void* _nilRefType;
typedef void* _chpl_object;
typedef void* _chpl_value;
typedef void* chpl_opaque;
typedef void* c_void_ptr;
typedef const char* c_string;
typedef const char* c_string_copy;

typedef char int8_t;
typedef short int16_t;
typedef int int32_t;
typedef long int64_t;
typedef uchar uint8_t;
typedef ushort uint16_t;
typedef uint uint32_t;
typedef ulong uint64_t;

#ifndef __cplusplus
typedef _Bool chpl_bool;
#else
typedef bool chpl_bool;
#endif

typedef  int8_t    int_least8_t;
typedef  int16_t   int_least16_t;
typedef  int32_t   int_least32_t;
typedef  int64_t   int_least64_t;

typedef uint8_t   uint_least8_t;
typedef uint16_t  uint_least16_t;
typedef uint32_t  uint_least32_t;
typedef uint64_t  uint_least64_t;

typedef  int8_t    int_fast8_t;
typedef  int       int_fast16_t;
typedef  int32_t   int_fast32_t;
typedef  int64_t   int_fast64_t;

typedef uint8_t   uint_fast8_t;
typedef unsigned  uint_fast16_t;
typedef uint32_t  uint_fast32_t;
typedef uint64_t  uint_fast64_t;

typedef int_least8_t atomic_int_least8_t;
typedef int_least16_t atomic_int_least16_t;
typedef int_least32_t atomic_int_least32_t;
typedef int_least64_t atomic_int_least64_t;
typedef uint_least8_t atomic_uint_least8_t;
typedef uint_least16_t atomic_uint_least16_t;
typedef uint_least32_t atomic_uint_least32_t;
typedef uint_least64_t atomic_uint_least64_t;
typedef chpl_bool atomic_bool;
typedef uint64_t atomic__real64;
typedef uint32_t atomic__real32;



# define INT8_C(c)      c
# define INT16_C(c)     c
# define INT32_C(c)     c
# define INT64_C(c)    c ## LL

/* Unsigned.  */
# define UINT8_C(c)     c ## U
# define UINT16_C(c)    c ## U
# define UINT32_C(c)    c ## U
# define UINT64_C(c)   c ## ULL

typedef int32_t chpl__class_id;

// macros for specifying the correct C literal type
#define INT8( i)   ((int8_t)(INT8_C(i)))
#define INT16( i)  ((int16_t)(INT16_C(i)))
#define INT32( i)  ((int32_t)(INT32_C(i)))
#define INT64( i)  ((int64_t)(INT64_C(i)))
#define UINT8( i)  ((uint8_t)(UINT8_C(i)))
#define UINT16( i) ((uint16_t)(UINT16_C(i)))
#define UINT32( i) ((uint32_t)(UINT32_C(i)))
#define UINT64( i) ((uint64_t)(UINT64_C(i)))

typedef struct {
  int32_t node;
  int32_t subloc;
} chpl_localeID_t;

static inline
chpl_localeID_t chpl_gen_gpu_getLocaleID(void)
{
  chpl_localeID_t localeID = {0,0};
  return localeID;
}

