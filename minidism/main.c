#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

#include "decoder.h"
#include "format.h"

/* ---------- helpers ---------- */

#if defined(_MSC_VER)
static FILE* xfopen_rb(const char* path) {
    FILE* f = NULL;
    return (fopen_s(&f, path, "rb") == 0) ? f : NULL;
}
static FILE* xfopen_wt(const char* path) {
    FILE* f = NULL;
    return (fopen_s(&f, path, "w") == 0) ? f : NULL;
}
#else
static FILE* xfopen_rb(const char* path) { return fopen(path, "rb"); }
static FILE* xfopen_wt(const char* path) { return fopen(path, "w"); }
#endif

static unsigned char* load_file(const char* path, size_t* out_len) {
    FILE* f = xfopen_rb(path);
    if (!f) return NULL;

    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long sz = ftell(f);
    if (sz <= 0) { fclose(f); return NULL; }
    if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return NULL; }

    unsigned char* buf = (unsigned char*)malloc((size_t)sz);
    if (!buf) { fclose(f); return NULL; }

    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);

    if (rd != (size_t)sz) {
        free(buf);
        return NULL;
    }

    *out_len = (size_t)sz;
    return buf;
}

static void usage(const char* exe) {
    fprintf(stderr,
        "Usage: %s -i <input.bin> [-o out.txt] [-a 0xBASE] [-n BYTES] [--hex] [--count] [--nobuf]\n",
        exe);
}

/* ---------- main ---------- */

int main(int argc, char** argv) {
    const char* inPath = NULL;
    const char* outPath = NULL;
    uint32_t base = 0;
    int showHex = 0;
    int limit = -1;
    int countOnly = 0;
    int useBuffering = 1;

    /* --- parse args --- */
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "-i") && i + 1 < argc) {
            inPath = argv[++i];
        }
        else if (!strcmp(argv[i], "-o") && i + 1 < argc) {
            outPath = argv[++i];
        }
        else if (!strcmp(argv[i], "-a") && i + 1 < argc) {
            base = (uint32_t)strtoul(argv[++i], NULL, 0);
        }
        else if (!strcmp(argv[i], "-n") && i + 1 < argc) {
            limit = atoi(argv[++i]);
        }
        else if (!strcmp(argv[i], "--hex")) {
            showHex = 1;
        }
        else if (!strcmp(argv[i], "--count")) {
            countOnly = 1;
        }
        else if (!strcmp(argv[i], "--nobuf")) {
            useBuffering = 0;
        }
        else {
            usage(argv[0]);
            return 1;
        }
    }

    if (!inPath) {
        usage(argv[0]);
        return 1;
    }

    /* --- load input file --- */
    size_t len = 0;
    unsigned char* buf = load_file(inPath, &len);
    if (!buf) {
        fprintf(stderr, "Failed to read %s\n", inPath);
        return 1;
    }

    if (limit >= 0 && (size_t)limit < len) {
        len = (size_t)limit;
    }

    /* --- setup output (unless --count) --- */
    FILE* out = NULL;
    char* ioBuf = NULL;
    const size_t IO_BUF_SIZE = 8u * 1024u * 1024u; /* 8 MB */

    if (!countOnly) {
        out = stdout;
        if (outPath) {
            out = xfopen_wt(outPath);
            if (!out) {
                fprintf(stderr, "Failed to open %s\n", outPath);
                free(buf);
                return 1;
            }
        }

        if (useBuffering && out != stdout) {
            ioBuf = (char*)malloc(IO_BUF_SIZE);
            if (ioBuf) {
                if (setvbuf(out, ioBuf, _IOFBF, IO_BUF_SIZE) != 0) {
                    free(ioBuf);
                    ioBuf = NULL;
                }
            }
        }

    }

    decoder_init();

    int off = 0;
    char text[128];
    char hexbuf[64];

    /* ============================================================
       COUNT-ONLY MODE (decode-only, no formatting / no printing)
       ============================================================ */
    if (countOnly) {
        uint64_t instrs = 0;
        uint64_t unknown = 0;
        uint64_t bytes = 0;

        while (off < (int)len) {
            int consumed = decode_one(
                buf,
                (int)len - off,
                off,
                base,
                text,
                (int)sizeof(text),
                0 /* showHex disabled */
            );

            if (consumed <= 0) {
                off += 1;
                bytes += 1;
                unknown += 1;
                instrs += 1;
            }
            else {
                off += consumed;
                bytes += (uint64_t)consumed;
                instrs += 1;
            }
        }

        printf("count=%" PRIu64 " unknown=%" PRIu64 " bytes=%" PRIu64 "\n",
            instrs, unknown, bytes);

        free(buf);
        return 0;
    }

    /* ============================================================
       NORMAL DISASSEMBLY MODE
       ============================================================ */
    while (off < (int)len) {
        int consumed = decode_one(
            buf,
            (int)len - off,
            off,
            base,
            text,
            (int)sizeof(text),
            showHex
        );

        if (consumed <= 0) {
            /* unknown -> db 0x?? */
            char onehex[8] = { 0 };
            if (showHex) {
                fmt_hex_bytes(&buf[off], 1, onehex, (int)sizeof(onehex));
            }

            char dbtxt[32];
            snprintf(dbtxt, sizeof(dbtxt), "db 0x%02X", buf[off]);

            print_line(out,
                base + (uint32_t)off,
                showHex ? onehex : NULL,
                dbtxt);

            off += 1;
        }
        else {
            hexbuf[0] = 0;
            if (showHex) {
                fmt_hex_bytes(buf + off, consumed, hexbuf, (int)sizeof(hexbuf));
            }

            print_line(out,
                base + (uint32_t)off,
                showHex ? hexbuf : NULL,
                text);

            off += consumed;
        }
    }

    if (out && out != stdout) {
        fclose(out);
    }
    if (ioBuf) {
        free(ioBuf);
    }

    free(buf);
    return 0;
}
