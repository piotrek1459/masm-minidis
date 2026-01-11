// minidismcpp.cpp
// Standalone C++ disassembler CLI (no Visual Studio integration required)
// Supports the same instruction subset as your ASM backend (phase 4+):
//  - nop, ret, int3
//  - push/pop r32
//  - mov r32, imm32 (B8+rd)
//  - mov r32, r/m32 (8B /r)
//  - mov r/m32, r32 (89 /r)
//  - call rel32 (E8), jmp rel32 (E9), jmp rel8 (EB)
//  - je rel8 (74)
//  - 0F 80–8F Jcc rel32
//  - FF /2 call r/m32
//  - FF /4 jmp  r/m32
//
// Output format matches: "%08X:  <bytes padded to col> <mnemonic>\n"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <iomanip>
#include <sstream>
#include <fcntl.h>
#include <io.h>



static const char* REG32[8] = {"eax","ecx","edx","ebx","esp","ebp","esi","edi"};

static std::string bytes_to_string(const std::vector<uint8_t>& bytes) {
    std::ostringstream oss;
    oss << std::uppercase << std::hex << std::setfill('0');
    for (size_t i = 0; i < bytes.size(); ++i) {
        if (i) oss << ' ';
        oss << std::setw(2) << (unsigned)bytes[i];
    }
    return oss.str();
}

static std::string hex_u32(uint32_t v) {
    char b[16];
    std::snprintf(b, sizeof(b), "0x%08X", v);
    return b;
}

static std::string hex_disp(int32_t disp, bool force8 = false) {
    // Match your expected formatting:
    //  -0x08 (two hex digits for small)
    //  +0x10
    //  +0x12345678 (8 hex digits for larger)
    uint32_t a = (disp < 0) ? (uint32_t)(-disp) : (uint32_t)disp;
    bool small = force8 || (a <= 0xFF);

    char b[32];
    if (small) std::snprintf(b, sizeof(b), "0x%02X", (unsigned)a);
    else       std::snprintf(b, sizeof(b), "0x%08X", (unsigned)a);

    if (disp < 0) return std::string("-") + b;
    if (disp > 0) return std::string("+") + b;
    return "0x00";
}

struct ModRM {
    uint8_t mod{};
    uint8_t reg{};
    uint8_t rm{};
};

static bool read_u8(const uint8_t* code, size_t len, size_t off, uint8_t& out) {
    if (off >= len) return false;
    out = code[off];
    return true;
}
static bool read_u32(const uint8_t* code, size_t len, size_t off, uint32_t& out) {
    if (off + 4 > len) return false;
    out = (uint32_t)code[off]
        | ((uint32_t)code[off+1] << 8)
        | ((uint32_t)code[off+2] << 16)
        | ((uint32_t)code[off+3] << 24);
    return true;
}
static bool read_i8(const uint8_t* code, size_t len, size_t off, int8_t& out) {
    uint8_t b;
    if (!read_u8(code,len,off,b)) return false;
    out = (int8_t)b;
    return true;
}
static bool read_i32(const uint8_t* code, size_t len, size_t off, int32_t& out) {
    uint32_t u;
    if (!read_u32(code,len,off,u)) return false;
    out = (int32_t)u;
    return true;
}

static bool decode_modrm(uint8_t b, ModRM& m) {
    m.mod = (b >> 6) & 3;
    m.reg = (b >> 3) & 7;
    m.rm  = (b >> 0) & 7;
    return true;
}

// Formats r/m32 operand. Returns operand string and sets consumed extra bytes after ModRM.
static bool format_rm32(
    const uint8_t* code, size_t code_len,
    size_t after_modrm_off,
    const ModRM& m,
    std::string& out_operand,
    size_t& extra_consumed
) {
    extra_consumed = 0;

    if (m.mod == 3) {
        // register direct
        out_operand = REG32[m.rm];
        return true;
    }

    // memory addressing
    std::string expr;

    auto add_term = [&](const std::string& t) {
        if (t.empty()) return;
        if (!expr.empty()) expr += "+";
        expr += t;
    };

    // SIB handling when rm == 4 (and mod != 3)
    if (m.rm == 4) {
        uint8_t sib;
        if (!read_u8(code, code_len, after_modrm_off, sib)) return false;
        extra_consumed += 1;

        uint8_t ss = (sib >> 6) & 3;
        uint8_t index = (sib >> 3) & 7;
        uint8_t base  = (sib >> 0) & 7;

        uint32_t scale = 1u << ss;

        bool has_base = true;
        bool base_is_disp32 = (m.mod == 0 && base == 5);

        if (base_is_disp32) has_base = false;

        // base first (if present)
        if (has_base) {
            add_term(REG32[base]);
        }

        // then index (index==4 means none)
        if (index != 4) {
            if (scale == 1) add_term(REG32[index]);
            else {
                char t[32];
                std::snprintf(t, sizeof(t), "%s*%u", REG32[index], (unsigned)scale);
                add_term(t);
            }
        }


        // displacement
        if (m.mod == 1) {
            int8_t d8;
            if (!read_i8(code, code_len, after_modrm_off + extra_consumed, d8)) return false;
            extra_consumed += 1;

            if (expr.empty()) {
                // rare, but keep consistent
                uint32_t v = (uint32_t)(int32_t)d8;
                expr = hex_u32(v);
            } else if (d8 != 0) {
                // show +/- 0xNN
                int32_t d = (int32_t)d8;
                std::string disp = hex_disp(d, true);
                if (disp[0] == '+') add_term(disp.substr(1));
                else if (disp[0] == '-') expr += disp; // keeps "-0x08" without extra '+'
            }
        } else if (m.mod == 2 || base_is_disp32) {
            int32_t d32;
            if (!read_i32(code, code_len, after_modrm_off + extra_consumed, d32)) return false;
            extra_consumed += 4;

            if (expr.empty()) {
                expr = hex_u32((uint32_t)d32);
            } else if (d32 != 0) {
                // expected uses +0x12345678, or -0x....
                std::string disp = (d32 < 0) ? hex_disp(d32, false) : ("+" + hex_u32((uint32_t)d32));
                if (disp[0] == '+') add_term(disp.substr(1));
                else expr += disp;
            }
        }

        out_operand = "[" + expr + "]";
        return true;
    }

    // Non-SIB addressing
    if (m.mod == 0 && m.rm == 5) {
        // disp32 absolute
        uint32_t disp32;
        if (!read_u32(code, code_len, after_modrm_off, disp32)) return false;
        extra_consumed += 4;
        out_operand = "[" + hex_u32(disp32) + "]";
        return true;
    }

    // base register
    add_term(REG32[m.rm]);

    if (m.mod == 1) {
        int8_t d8;
        if (!read_i8(code, code_len, after_modrm_off, d8)) return false;
        extra_consumed += 1;
        if (d8 != 0) {
            int32_t d = (int32_t)d8;
            std::string disp = hex_disp(d, true);
            if (disp[0] == '+') add_term(disp.substr(1));
            else expr += disp; // "-0x08"
        }
    } else if (m.mod == 2) {
        int32_t d32;
        if (!read_i32(code, code_len, after_modrm_off, d32)) return false;
        extra_consumed += 4;
        if (d32 != 0) {
            std::string disp = (d32 < 0) ? hex_disp(d32, false) : ("+" + hex_u32((uint32_t)d32));
            if (disp[0] == '+') add_term(disp.substr(1));
            else expr += disp;
        }
    }

    out_operand = "[" + expr + "]";
    return true;
}

static const char* jcc_mnemonic(uint8_t cc) {
    // 0F 80..8F
    switch (cc & 0x0F) {
        case 0x0: return "jo";
        case 0x1: return "jno";
        case 0x2: return "jb";
        case 0x3: return "jnb";
        case 0x4: return "je";
        case 0x5: return "jne";
        case 0x6: return "jbe";
        case 0x7: return "jnbe";
        case 0x8: return "js";
        case 0x9: return "jns";
        case 0xA: return "jp";
        case 0xB: return "jnp";
        case 0xC: return "jl";
        case 0xD: return "jnl";
        case 0xE: return "jle";
        case 0xF: return "jg";
        default:  return "jcc";
    }
}

struct Decoded {
    size_t len{};
    std::string text;
};

static Decoded decode_one(const uint8_t* code, size_t code_len, size_t off, uint32_t ip) {
    Decoded d;
    d.len = 1;
    d.text = "db 0x??";

    uint8_t op;
    if (!read_u8(code, code_len, off, op)) {
        d.len = 0;
        d.text = "db 0x??";
        return d;
    }

    // 1-byte simple ops
    if (op == 0x90) { d.len = 1; d.text = "nop"; return d; }
    if (op == 0xC3) { d.len = 1; d.text = "ret"; return d; }
    if (op == 0xCC) { d.len = 1; d.text = "int3"; return d; }

    // push/pop r32
    if ((op & 0xF8) == 0x50) {
        d.len = 1;
        d.text = std::string("push ") + REG32[op & 7];
        return d;
    }
    if ((op & 0xF8) == 0x58) {
        d.len = 1;
        d.text = std::string("pop ") + REG32[op & 7];
        return d;
    }

    // mov r32, imm32 (B8+rd)
    if ((op & 0xF8) == 0xB8) {
        uint32_t imm;
        if (!read_u32(code, code_len, off + 1, imm)) return d;
        d.len = 5;
        d.text = std::string("mov ") + REG32[op & 7] + ", " + hex_u32(imm);
        return d;
    }

    // call/jmp rel
    if (op == 0xE8) {
        int32_t rel;
        if (!read_i32(code, code_len, off + 1, rel)) return d;
        d.len = 5;
        uint32_t target = ip + (uint32_t)d.len + (uint32_t)rel;
        d.text = std::string("call ") + hex_u32(target);
        return d;
    }
    if (op == 0xE9) {
        int32_t rel;
        if (!read_i32(code, code_len, off + 1, rel)) return d;
        d.len = 5;
        uint32_t target = ip + (uint32_t)d.len + (uint32_t)rel;
        d.text = std::string("jmp ") + hex_u32(target);
        return d;
    }
    if (op == 0xEB) {
        int8_t rel;
        if (!read_i8(code, code_len, off + 1, rel)) return d;
        d.len = 2;
        uint32_t target = ip + (uint32_t)d.len + (int32_t)rel;
        d.text = std::string("jmp ") + hex_u32(target);
        return d;
    }
    if (op == 0x74) {
        int8_t rel;
        if (!read_i8(code, code_len, off + 1, rel)) return d;
        d.len = 2;
        uint32_t target = ip + (uint32_t)d.len + (int32_t)rel;
        d.text = std::string("je ") + hex_u32(target);
        return d;
    }

    // 0F prefix: Jcc rel32
    if (op == 0x0F) {
        uint8_t op2;
        if (!read_u8(code, code_len, off + 1, op2)) return d;
        if (op2 >= 0x80 && op2 <= 0x8F) {
            int32_t rel;
            if (!read_i32(code, code_len, off + 2, rel)) return d;
            d.len = 6;
            uint32_t target = ip + (uint32_t)d.len + (uint32_t)rel;
            d.text = std::string(jcc_mnemonic(op2)) + " " + hex_u32(target);
            return d;
        }
        // unknown 0F xx
        d.len = 2;
        d.text = "db 0x0F";
        return d;
    }

    // mov r32, r/m32 (8B /r)
    if (op == 0x8B || op == 0x89) {
        uint8_t mbyte;
        if (!read_u8(code, code_len, off + 1, mbyte)) return d;
        ModRM m{};
        decode_modrm(mbyte, m);

        std::string rm_str;
        size_t extra = 0;
        if (!format_rm32(code, code_len, off + 2, m, rm_str, extra)) return d;

        d.len = 2 + extra;

        if (op == 0x8B) {
            // mov reg, r/m
            d.text = std::string("mov ") + REG32[m.reg] + ", " + rm_str;
        } else {
            // mov r/m, reg
            d.text = std::string("mov ") + rm_str + ", " + REG32[m.reg];
        }
        return d;
    }

    // FF group: /2 call r/m32, /4 jmp r/m32
    if (op == 0xFF) {
        uint8_t mbyte;
        if (!read_u8(code, code_len, off + 1, mbyte)) return d;
        ModRM m{};
        decode_modrm(mbyte, m);

        std::string rm_str;
        size_t extra = 0;
        if (!format_rm32(code, code_len, off + 2, m, rm_str, extra)) return d;

        d.len = 2 + extra;

        if (m.reg == 2) {
            d.text = std::string("call ") + rm_str;
            return d;
        }
        if (m.reg == 4) {
            d.text = std::string("jmp ") + rm_str;
            return d;
        }

        // other FF /n not supported
        d.text = "db 0xFF";
        d.len = 1;
        return d;
    }

    // fallback: print raw byte
    {
        char b[32];
        std::snprintf(b, sizeof(b), "db 0x%02X", (unsigned)op);
        d.text = b;
        d.len = 1;
        return d;
    }
}

static void print_line(uint32_t ip, const uint8_t* bytes, size_t n, const std::string& asm_text) {
    char bstr[256];
    bstr[0] = '\0';

    for (size_t i = 0; i < n; ++i) {
        char tmp[8];
        std::snprintf(tmp, sizeof(tmp), "%02X", (unsigned)bytes[i]);
        std::strcat(bstr, tmp);
        if (i + 1 < n) std::strcat(bstr, " ");
    }

    const int blen = (int)std::strlen(bstr);

    std::printf("%08X:  %s", ip, bstr);

    // Pad short byte strings so that mnemonics align like the expected files.
    // For 1..5 bytes, expected uses padding to 17 and then one space.
    // For 6+ bytes (blen >= 17), expected uses two spaces (no extra padding).
    if (blen < 17) {
        for (int i = 0; i < (17 - blen); ++i) std::putchar(' ');
        std::putchar(' '); // separator
    } else {
        std::putchar(' ');
        std::putchar(' '); // two spaces for 6+ bytes
    }

    std::printf("%s\n", asm_text.c_str());
}


static uint32_t parse_u32(const char* s) {
    // accepts hex "0x..." or plain decimal
    if (!s) return 0;
    if (std::strlen(s) > 2 && (s[0]=='0') && (s[1]=='x' || s[1]=='X')) {
        return (uint32_t)std::strtoul(s + 2, nullptr, 16);
    }
    // also allow hex without 0x (your tests pass 0x00401000 as BASE)
    // but keep decimal fallback
    return (uint32_t)std::strtoul(s, nullptr, 0);
}

static void usage() {
    std::fprintf(stderr,
        "minidismcpp.exe -i <input.bin> -a <base_addr> [--hex]\n"
        "Example: minidismcpp.exe -i ..\\test_data\\pushpop.bin -a 0x00401000 --hex\n"
    );
}

int main(int argc, char** argv) {
    const char* in_path = nullptr;
    uint32_t base = 0;
    bool hex_on = false;

    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "-i") == 0 && i + 1 < argc) {
            in_path = argv[++i];
        } else if (std::strcmp(argv[i], "-a") == 0 && i + 1 < argc) {
            base = parse_u32(argv[++i]);
        } else if (std::strcmp(argv[i], "--hex") == 0) {
            hex_on = true; // kept for CLI parity (we always print hex like your expected)
        } else if (std::strcmp(argv[i], "-h") == 0 || std::strcmp(argv[i], "--help") == 0) {
            usage();
            return 0;
        }
    }

    (void)hex_on; // currently unused; output is hex to match expected

    if (!in_path) {
        usage();
        return 2;
    }

    std::FILE* f = std::fopen(in_path, "rb");
    if (!f) {
        std::fprintf(stderr, "Failed to open input: %s\n", in_path);
        return 2;
    }

    std::fseek(f, 0, SEEK_END);
    long sz = std::ftell(f);
    std::fseek(f, 0, SEEK_SET);

    if (sz < 0) {
        std::fprintf(stderr, "Failed to read file size.\n");
        std::fclose(f);
        return 2;
    }

    std::vector<uint8_t> buf((size_t)sz);
    size_t got = std::fread(buf.data(), 1, buf.size(), f);
    std::fclose(f);

    if (got != buf.size()) {
        std::fprintf(stderr, "Failed to read whole file.\n");
        return 2;
    }

    size_t off = 0;
    uint32_t ip = base;

    while (off < buf.size()) {
        Decoded d = decode_one(buf.data(), buf.size(), off, ip);
        if (d.len == 0) break;
        if (off + d.len > buf.size()) d.len = 1; // safety

        print_line(ip, buf.data() + off, d.len, d.text);

        off += d.len;
        ip += (uint32_t)d.len;
    }

    return 0;
}
