#ifndef SMOOTH_MARKDOWN_RUST_H
#define SMOOTH_MARKDOWN_RUST_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Owned bytes; copy/decode before freeing. Free exactly once via this library. */
typedef struct SmrBuffer {
    const uint8_t *data;
    size_t len;
    void *owner;
} SmrBuffer;
enum { SMR_OK = 0, SMR_INVALID_INPUT = 1, SMR_LIMIT_EXCEEDED = 2, SMR_INTERNAL_ERROR = 3 };
enum { SMR_GFM = 1, SMR_NATIVE_EXTENSIONS = 2 };
uint32_t smr_abi_version(void);
int32_t smr_parse_utf16(const uint16_t *source, size_t length, uint32_t options, SmrBuffer *result);
void smr_buffer_free(SmrBuffer *buffer);
#ifdef __cplusplus
}
#endif
#endif
