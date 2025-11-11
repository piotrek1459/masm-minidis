#include "format.h"
#include <string.h>

void fmt_addr(uint32_t addr, char* out, int cap) {
    // 8 hex digits, zero-padded
    snprintf(out, cap, "%08X", addr);
}

int fmt_hex_bytes(const unsigned char* src, int n, char* out, int cap) {
    int used = 0;
    for (int i = 0; i < n; ++i) {
        int w = snprintf(out + used, (used < cap ? cap - used : 0),
            i ? " %02X" : "%02X", src[i]);
        used += w;
    }
    return used;
}

void print_line(FILE* f, uint32_t address, const char* hex, const char* text) {
    char addr[16];
    fmt_addr(address, addr, sizeof addr);

    if (hex && *hex) {
        fprintf(f, "%s:  %-16s  %s\n", addr, hex, text);
    }
    else {
        fprintf(f, "%s:  %s\n", addr, text);
    }
}
