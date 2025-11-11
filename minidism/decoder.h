#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

    // Initializes tables/state (currently a no-op).
    void __cdecl decoder_init(void);

    // Decodes one instruction starting at buf[off] within len bytes.
    // Writes a textual form to `out` (capacity outcap) when recognized.
    // Returns number of bytes consumed (>0) on success, or 0 if unknown/incomplete.
    int __cdecl decode_one(
        const uint8_t* buf,
        int            len,
        int            off,
        uint32_t       base,
        char* out,
        int            outcap,
        int            hexOn
    );

#ifdef __cplusplus
}
#endif
