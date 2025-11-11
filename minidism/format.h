#pragma once
#include <stdint.h>
#include <stdio.h>

// 8-digit hex address as string: e.g., "00401000"
void fmt_addr(uint32_t addr, char* out, int cap);

// Hex bytes for one instruction: e.g., "90 C3" (src points into buffer)
int  fmt_hex_bytes(const unsigned char* src, int n, char* out, int cap);

// Print one disassembly line.
// If `hex` is non-null, it will be printed between address and text.
void print_line(FILE* f, uint32_t address, const char* hex, const char* text);
