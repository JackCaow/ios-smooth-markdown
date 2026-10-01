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
enum { SMR_OK = 0, SMR_INVALID_INPUT = 1, SMR_LIMIT_EXCEEDED = 2, SMR_INTERNAL_ERROR = 3, SMR_CALLBACK_ERROR = 4 };
enum { SMR_GFM = 1, SMR_NATIVE_EXTENSIONS = 2, SMR_ESCAPE_HTML = 4, SMR_TRANSPARENT_TABLE_PARTS = 8, SMR_HOST_FENCED_BLOCKS = 16 };
uint32_t smr_abi_version(void);
int32_t smr_parse_utf16(const uint16_t *source, size_t length, uint32_t options, SmrBuffer *result);
typedef struct SmrMatch { uint32_t consumed; uint32_t id; } SmrMatch;
typedef int32_t (*SmrInlineCallback)(void *,const uint16_t *,size_t,uint32_t,uint32_t,SmrMatch *);
typedef int32_t (*SmrBlockCallback)(void *,const uint16_t *const *,const size_t *,size_t,uint32_t,uint32_t,SmrMatch *);
typedef int32_t (*SmrInlineContextCallback)(void *,const uint16_t *,size_t,int32_t);
typedef int32_t (*SmrBlockContextCallback)(void *,const uint16_t *const *,const size_t *,size_t,int32_t);
/* Optional scope notifications: begin=1, end=0. Nested scopes unwind in order.
   They permit bridge adapters to reuse immutable host contexts rather than copying per candidate. */
typedef struct SmrHooks { void *context; SmrInlineCallback inline_callback; SmrBlockCallback block_callback;
    SmrInlineContextCallback inline_context; SmrBlockContextCallback block_context; } SmrHooks;
/* SMR_HOST_FENCED_BLOCKS permits a block hook to claim a complete fenced construct
   at its opening line. Ordinary fenced bodies are always protected.
   Synchronous borrowed callbacks: 0 miss, 1 match, negative abort. Inline consumed is UTF16;
   block consumed is line count. IDs must be positive and are returned as Custom.label. */
int32_t smr_parse_with_hooks_utf16(const uint16_t *,size_t,uint32_t,const SmrHooks *,SmrBuffer *);
int32_t smr_parse_inline_utf16(const uint16_t *,size_t,uint32_t,const uint8_t *,size_t,const SmrHooks *,SmrBuffer *);
/* Mutable AST input uses explicit SMR1 strings. Output is raw little-endian UTF16. */
int32_t smr_render_ast_utf16(const uint8_t *,size_t,uint32_t,SmrBuffer *);
int32_t smr_export_html_utf16(const uint16_t *,size_t,uint32_t,SmrBuffer *);
void smr_buffer_free(SmrBuffer *buffer);
#ifdef __cplusplus
}
#endif
#endif
