#include <assert.h>    // for assert
#include <stdbool.h>   // for bool
#include <stddef.h>    // nor NULL
#include <stdint.h>    // for int32_t, etc
#include <stdio.h>     // printf etc
#include <string.h>    // for memcpy
#include <sys/mman.h>  // for mmap

#include "greatest.h"

// Objects

// word definition
typedef int64_t word;
typedef uint64_t uword;

// bit size
const int kBitsPerByte = 8;                         // bits
const int kWordSize = sizeof(word);                 // bytes
const int kBitsPerWord = kWordSize * kBitsPerByte;  // bits

// Integers
const unsigned int kIntegerTag = 0x0;
const unsigned int kIntegerTagMask = 0x3;
const unsigned int kIntegerShift = 2;
const unsigned int kIntegerBits = kBitsPerWord - kIntegerShift;
const word kIntegerMax = (1LL << ((kIntegerBits - 1) - 1));
const word kIntegerMin = -(1LL << (kIntegerBits - 1));

// Immediate tag
const unsigned int kImmediateTagMask = 0x3f;

// Chars
const unsigned int kCharTag = 0xf;    // 0b00001111
const unsigned int kCharMask = 0xff;  // 0b11111111
const unsigned int kCharShift = 8;

// Boolean
const unsigned int kBoolTag = 0x1f;   // 0b0011111
const unsigned int kBoolMask = 0x80;  // 0b10000000
const unsigned int kBoolShift = 7;

word Object_encode_integer(word value) {
  assert(value < kIntegerMax && "too big");
  assert(value > kIntegerMin && "too small");
  return value << kIntegerShift;
}

word Object_encode_char(char value) {
  return ((word)value << kCharShift | kCharTag);
}

char Object_decode_char(word value) {
  return (value >> kCharShift & kCharMask);
}

word Object_encode_bool(bool value) {
  return ((word)value << kBoolShift) | kBoolTag;
}

bool Object_decode_bool(word value) { return value & kBoolMask; }

word Object_true() { return Object_encode_bool(true); }

word Object_false() { return Object_encode_bool(false); }

word Object_nil() { return 0x2f; }

// End Objects

// AST

struct ASTNode;
typedef struct ASTNode ASTNode;

ASTNode *AST_new_integer(word value) {
  return (ASTNode *)Object_encode_integer(value);
}

bool AST_is_integer(ASTNode *node) {
  return ((word)node & kIntegerTagMask) == kIntegerTag;
}

word AST_get_integer(ASTNode *node) { return (word)node >> kIntegerShift; }

bool AST_is_char(ASTNode *node) {
  return ((word)node & kImmediateTagMask) == kCharTag;
}

char AST_get_char(ASTNode *node) { return Object_decode_char((word)node); }

ASTNode *AST_new_char(char value) {
  return (ASTNode *)Object_encode_char(value);
}

bool AST_is_bool(ASTNode *node) {
  return ((word)node & kImmediateTagMask) == kBoolTag;
}

bool AST_get_bool(ASTNode *node) { return Object_decode_bool((word)node); }

ASTNode *AST_new_bool(bool value) {
  return (ASTNode *)Object_encode_bool(value);
}

bool AST_is_nil(ASTNode *node) { return (word)node == Object_nil(); }

ASTNode *AST_nil() { return (ASTNode *)Object_nil(); }

// End AST

// Buffer

typedef unsigned char byte;

typedef enum {
  kWriteable,
  kExecutable,
} BufferState;

typedef struct {
  byte *address;
  BufferState state;
  size_t len;
  size_t capacity;
} Buffer;

byte *Buffer_alloc_writeable(size_t capacity) {
  byte *result = mmap(/*addr=*/NULL,
                      /*length=*/capacity,
                      /*prot=*/PROT_READ | PROT_WRITE,
                      /*flags=*/MAP_ANONYMOUS | MAP_PRIVATE,
                      /*filedes=*/-1,
                      /*offset=*/0);
  assert(result != MAP_FAILED);
  return result;
}

void Buffer_init(Buffer *result, size_t capacity) {
  result->address = Buffer_alloc_writeable(capacity);
  assert(result->address != MAP_FAILED);
  result->state = kWriteable;
  result->len = 0;
  result->capacity = capacity;
}

void Buffer_deinit(Buffer *buf) {
  munmap(buf->address, buf->capacity);
  buf->address = NULL;
  buf->len = 0;
  buf->capacity = 0;
}

int Buffer_make_executable(Buffer *buf) {
  int result = mprotect(buf->address, buf->len, PROT_EXEC);
  buf->state = kExecutable;
  return result;
}

byte Buffer_at8(Buffer *buf, size_t pos) { return buf->address[pos]; }

void Buffer_at_put8(Buffer *buf, size_t pos, byte b) { buf->address[pos] = b; }

word max(word left, word right) { return left > right ? left : right; }

void Buffer_ensure_capacity(Buffer *buf, word additional_capacity) {
  if (buf->len + additional_capacity <= buf->capacity) {
    return;
  }

  word new_capacity =
      max(buf->capacity * 2, buf->capacity + additional_capacity);
  byte *address = Buffer_alloc_writeable(new_capacity);
  memcpy(address, buf->address, buf->len);
  int result = munmap(buf->address, buf->capacity);
  assert(result == 0 && "munmap failed");
  buf->address = address;
  buf->capacity = new_capacity;
}

void Buffer_write8(Buffer *buf, byte b) {
  Buffer_ensure_capacity(buf, sizeof b);
  Buffer_at_put8(buf, buf->len++, b);
}

void Buffer_write32(Buffer *buf, int32_t value) {
  for (size_t i = 0; i < sizeof value; i++) {
    Buffer_write8(buf, (value >> (i * kBitsPerByte)) & 0xff);
  }
}

// End Buffer

// Emit

typedef enum {
  kRax = 0,
  kRcx,
  kRdx,
  kRbx,
  kRsp,
  kRbp,
  kRsi,
  kRdi,
} Register;

static const byte kRexPrefix = 0x48;

void Emit_mov_reg_imm32(Buffer *buf, Register dst, int32_t src) {
  Buffer_write8(buf, kRexPrefix);
  Buffer_write8(buf, 0xc7);
  Buffer_write8(buf, 0xc0 + dst);
  Buffer_write32(buf, src);
}

void Emit_ret(Buffer *buf) { Buffer_write8(buf, 0xc3); }

// End Emit

// Compile

int Compile_expr(Buffer *buf, ASTNode *node) {
  if (AST_is_integer(node)) {
    word value = AST_get_integer(node);
    Emit_mov_reg_imm32(buf, kRax, Object_encode_integer(value));
    return 0;
  }
  if (AST_is_char(node)) {
    char value = AST_get_char(node);
    Emit_mov_reg_imm32(buf, kRax, Object_encode_char(value));
    return 0;
  }
  if (AST_is_bool(node)) {
    bool value = AST_get_bool(node);
    Emit_mov_reg_imm32(buf, kRax, Object_encode_bool(value));
    return 0;
  }

  assert(0 && "unexpected node type");
}

int Compile_function(Buffer *buf, ASTNode *node) {
  int result = Compile_expr(buf, node);
  if (result != 0) {
    return result;
  }

  Emit_ret(buf);
  return 0;
}

typedef int (*JitFunction)();

// End Compile

// Testing

#define EXPECT_EQUALS_BYTES(buf, arr) \
  ASSERT_MEM_EQ(arr, (buf)->address, sizeof arr)

word Testing_execute_expr(Buffer *buf) {
  assert(buf != NULL);
  assert(buf->address != NULL);
  assert(buf->state == kExecutable);
  // The pointer-pointer cast is allowed but the underLying
  // data-to-function-pointer back-and-forth is only guaramteed to work on
  // POSIX systems (because of eg dLsym).
  JitFunction function = *(JitFunction *)(&buf->address);
  return function();
}

#define RUN_BUFFER_TEST(test_name)       \
  do {                                   \
    Buffer buf;                          \
    Buffer_init(&buf, 1);                \
    GREATEST_RUN_TEST1(test_name, &buf); \
    Buffer_deinit(&buf);                 \
  } while (0)
// End Testing

// Tests

TEST encode_positive_integer(void) {
  ASSERT_EQ(0x0, Object_encode_integer(0));
  ASSERT_EQ(0x4, Object_encode_integer(1));
  ASSERT_EQ(0x28, Object_encode_integer(10));
  PASS();
}

TEST encode_negative_integer(void) {
  ASSERT_EQ(0x0, Object_encode_integer(0));
  ASSERT_EQ((word)0xfffffffffffffffc, Object_encode_integer(-1));
  PASS();
}

TEST buffer_write8_increases_length(void) {
  Buffer buf;
  Buffer_init(&buf, 5);
  ASSERT_EQ(buf.len, 0);
  Buffer_write8(&buf, 0xdb);
  ASSERT_EQ(Buffer_at8(&buf, 0), 0xdb);
  ASSERT_EQ(buf.len, 1);
  Buffer_deinit(&buf);
  PASS();
}

TEST buffer_write8_expands_buffer(void) {
  Buffer buf;
  Buffer_init(&buf, 1);
  ASSERT_EQ(buf.capacity, 1);
  ASSERT_EQ(buf.len, 0);
  Buffer_write8(&buf, 0xdb);
  Buffer_write8(&buf, 0xef);
  ASSERT(buf.capacity > 1);
  ASSERT_EQ(buf.len, 2);
  Buffer_deinit(&buf);
  PASS();
}

TEST buffer_write32_expands_buffer(Buffer *buf) {
  ASSERT_EQ(buf->capacity, 1);
  ASSERT_EQ(buf->len, 0);
  Buffer_write32(buf, 0xdeadbeef);
  ASSERT(buf->capacity > 1);
  ASSERT_EQ(buf->len, 4);
  PASS();
}

TEST buffer_write32_writes_little_endian(Buffer *buf) {
  Buffer_write32(buf, 0xdeadbeef);
  ASSERT_EQ(Buffer_at8(buf, 0), 0xef);
  ASSERT_EQ(Buffer_at8(buf, 1), 0xbe);
  ASSERT_EQ(Buffer_at8(buf, 2), 0xad);
  ASSERT_EQ(Buffer_at8(buf, 3), 0xde);
  PASS();
}

TEST compile_positive_integer(void) {
  word value = 123;
  ASTNode *node = AST_new_integer(value);
  Buffer buf;
  Buffer_init(&buf, 10);
  int compile_result = Compile_function(&buf, node);
  ASSERT_EQ(compile_result, 0);
  // mov eax, imm(123); ret
  byte expected[] = {0x48, 0xc7, 0xc0, 0xec, 0x01, 0x00, 0x00, 0xc3};
  EXPECT_EQUALS_BYTES(&buf, expected);
  Buffer_make_executable(&buf);
  word result = Testing_execute_expr(&buf);
  ASSERT_EQ(result, Object_encode_integer(value));
  Buffer_deinit(&buf);
  PASS();
}

TEST compile_negative_integer(void) {
  word value = -123;
  ASTNode *node = AST_new_integer(value);
  Buffer buf;
  Buffer_init(&buf, 10);
  int compile_result = Compile_function(&buf, node);
  ASSERT_EQ(compile_result, 0);
  // mov eax, imm(123); ret
  byte expected[] = {0x48, 0xc7, 0xc0, 0x14, 0xfe, 0xff, 0xff, 0xc3};
  EXPECT_EQUALS_BYTES(&buf, expected);
  Buffer_make_executable(&buf);
  word result = Testing_execute_expr(&buf);
  ASSERT_EQ(result, Object_encode_integer(value));
  Buffer_deinit(&buf);
  PASS();
}

TEST compile_char(Buffer *buf) {
  char value = 'a';
  ASTNode *node = AST_new_char(value);
  int compile_result = Compile_function(buf, node);
  ASSERT_EQ(compile_result, 0);
  // mov eax, imm('a'); ret
  byte expected[] = {0x48, 0xc7, 0xc0, 0x0f, 0x61, 0x00, 0x00, 0xc3};
  EXPECT_EQUALS_BYTES(buf, expected);
  Buffer_make_executable(buf);
  word result = Testing_execute_expr(buf);
  ASSERT_EQ(result, Object_encode_char(value));
  PASS();
}

SUITE(object_tests) {
  RUN_TEST(encode_positive_integer);
  RUN_TEST(encode_negative_integer);
}

SUITE(buffer_tests) {
  RUN_TEST(buffer_write8_increases_length);
  RUN_TEST(buffer_write8_expands_buffer);
  RUN_BUFFER_TEST(buffer_write32_expands_buffer);
  RUN_BUFFER_TEST(buffer_write32_writes_little_endian);
}

SUITE(compiler_tests) {
  RUN_TEST(compile_positive_integer);
  RUN_TEST(compile_negative_integer);
  RUN_BUFFER_TEST(compile_char);
}

// End Tests

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
  GREATEST_MAIN_BEGIN();
  RUN_SUITE(object_tests);
  RUN_SUITE(buffer_tests);
  RUN_SUITE(compiler_tests);
  GREATEST_MAIN_END();
}
