#!/usr/bin/env python3
# Standalone Python disassembler backend for masm-minidis
# Matches the same subset as ASM/C++ backends:
# - nop, ret, int3
# - push/pop r32
# - mov r32, imm32 (B8+rd)
# - mov r32, r/m32 (8B /r)
# - mov r/m32, r32 (89 /r)
# - call rel32 (E8), jmp rel32 (E9), jmp rel8 (EB)
# - je rel8 (74)
# - 0F 80–8F Jcc rel32
# - FF /2 call r/m32
# - FF /4 jmp  r/m32
#
# Output formatting matches your normalized expected files:
# - bytes string built as "AA BB CC ..."
# - if len(bytes_str) < 17: pad to 17, then ONE space
# - else: TWO spaces
# - then mnemonic

from __future__ import annotations

import sys
from dataclasses import dataclass
from typing import Tuple, Optional

REG32 = ["eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi"]


def u32(x: int) -> int:
    return x & 0xFFFFFFFF


def hex_u32(v: int) -> str:
    return f"0x{u32(v):08X}"


def parse_u32(s: str) -> int:
    s = s.strip()
    if s.lower().startswith("0x"):
        return int(s[2:], 16) & 0xFFFFFFFF
    return int(s, 0) & 0xFFFFFFFF


def read_u8(buf: bytes, off: int) -> int:
    return buf[off]


def read_i8(buf: bytes, off: int) -> int:
    b = buf[off]
    return b - 256 if b >= 128 else b


def read_u32_le(buf: bytes, off: int) -> int:
    return int.from_bytes(buf[off:off + 4], "little", signed=False)


def read_i32_le(buf: bytes, off: int) -> int:
    return int.from_bytes(buf[off:off + 4], "little", signed=True)


@dataclass
class ModRM:
    mod: int
    reg: int
    rm: int


def decode_modrm(b: int) -> ModRM:
    return ModRM(mod=(b >> 6) & 3, reg=(b >> 3) & 7, rm=b & 7)


def format_disp8(d: int) -> str:
    # expects +/-0xNN with 2 digits
    if d < 0:
        return f"-0x{(-d) & 0xFF:02X}"
    if d > 0:
        return f"+0x{d & 0xFF:02X}"
    return ""


def format_disp32_signed(d: int) -> str:
    # expects +0x12345678 / -0x12345678
    if d < 0:
        return f"-0x{(-d) & 0xFFFFFFFF:08X}"
    if d > 0:
        return f"+0x{d & 0xFFFFFFFF:08X}"
    return ""


def bytes_to_str(b: bytes) -> str:
    return " ".join(f"{x:02X}" for x in b)


def print_line(ip: int, instr_bytes: bytes, text: str) -> None:
    bstr = bytes_to_str(instr_bytes)
    blen = len(bstr)

    # normalized expected formatting:
    # if blen < 17: pad to 17 then 1 space
    # else: 2 spaces
    if blen < 17:
        pad = " " * (17 - blen) + " "
    else:
        pad = "  "

    sys.stdout.write(f"{ip:08X}:  {bstr}{pad}{text}\n")


def jcc_mnemonic(cc: int) -> str:
    # cc = second byte in 0F 8x
    table = {
        0x0: "jo",  0x1: "jno", 0x2: "jb",  0x3: "jnb",
        0x4: "je",  0x5: "jne", 0x6: "jbe", 0x7: "jnbe",
        0x8: "js",  0x9: "jns", 0xA: "jp",  0xB: "jnp",
        0xC: "jl",  0xD: "jnl", 0xE: "jle", 0xF: "jg",
    }
    return table.get(cc & 0x0F, "jcc")


def format_rm32(buf: bytes, after_modrm: int, m: ModRM) -> Tuple[str, int]:
    """
    Returns (operand_str, extra_bytes_consumed_after_modrm)
    """
    if m.mod == 3:
        return REG32[m.rm], 0

    expr_parts: list[str] = []
    extra = 0

    def add_part(p: str) -> None:
        if p:
            expr_parts.append(p)

    # SIB when rm==4 and mod!=3
    if m.rm == 4:
        sib = read_u8(buf, after_modrm)
        extra += 1

        ss = (sib >> 6) & 3
        index = (sib >> 3) & 7
        base = sib & 7

        scale = 1 << ss

        base_is_disp32 = (m.mod == 0 and base == 5)
        has_base = not base_is_disp32

        # base first (to match expected: eax+ecx*4+...)
        if has_base:
            add_part(REG32[base])

        # index (index==4 means none)
        if index != 4:
            if scale == 1:
                add_part(REG32[index])
            else:
                add_part(f"{REG32[index]}*{scale}")

        # displacement
        if m.mod == 1:
            d8 = read_i8(buf, after_modrm + extra)
            extra += 1
            disp = format_disp8(d8)
            if disp.startswith("+"):
                add_part(disp[1:])
            elif disp.startswith("-"):
                # attach as "-0xNN" to the last expression without an extra '+'
                if expr_parts:
                    expr_parts[-1] = expr_parts[-1] + disp
                else:
                    add_part(disp)
        elif m.mod == 2 or base_is_disp32:
            d32 = read_i32_le(buf, after_modrm + extra)
            extra += 4
            if not expr_parts:
                # absolute
                add_part(hex_u32(d32))
            else:
                disp = format_disp32_signed(d32)
                if disp.startswith("+"):
                    add_part(disp[1:])
                elif disp.startswith("-"):
                    expr_parts[-1] = expr_parts[-1] + disp

        expr = "+".join(expr_parts) if expr_parts else ""
        return f"[{expr}]", extra

    # non-SIB addressing
    if m.mod == 0 and m.rm == 5:
        # disp32 absolute
        disp32 = read_u32_le(buf, after_modrm)
        extra += 4
        return f"[{hex_u32(disp32)}]", extra

    # base reg
    add_part(REG32[m.rm])

    if m.mod == 1:
        d8 = read_i8(buf, after_modrm)
        extra += 1
        disp = format_disp8(d8)
        if disp.startswith("+"):
            add_part(disp[1:])
        elif disp.startswith("-"):
            expr_parts[-1] = expr_parts[-1] + disp
    elif m.mod == 2:
        d32 = read_i32_le(buf, after_modrm)
        extra += 4
        disp = format_disp32_signed(d32)
        if disp.startswith("+"):
            add_part(disp[1:])
        elif disp.startswith("-"):
            expr_parts[-1] = expr_parts[-1] + disp

    expr = "+".join(expr_parts)
    return f"[{expr}]", extra


@dataclass
class Decoded:
    length: int
    text: str


def decode_one(buf: bytes, off: int, ip: int) -> Decoded:
    if off >= len(buf):
        return Decoded(0, "db 0x??")

    op = read_u8(buf, off)

    # 1-byte simple
    if op == 0x90:
        return Decoded(1, "nop")
    if op == 0xC3:
        return Decoded(1, "ret")
    if op == 0xCC:
        return Decoded(1, "int3")

    # push/pop r32
    if (op & 0xF8) == 0x50:
        return Decoded(1, f"push {REG32[op & 7]}")
    if (op & 0xF8) == 0x58:
        return Decoded(1, f"pop {REG32[op & 7]}")

    # mov r32, imm32 (B8+rd)
    if (op & 0xF8) == 0xB8:
        if off + 5 > len(buf):
            return Decoded(1, f"db 0x{op:02X}")
        imm = read_u32_le(buf, off + 1)
        return Decoded(5, f"mov {REG32[op & 7]}, {hex_u32(imm)}")

    # call/jmp rel32, jmp/je rel8
    if op == 0xE8:
        if off + 5 > len(buf):
            return Decoded(1, f"db 0x{op:02X}")
        rel = read_i32_le(buf, off + 1)
        target = u32(ip + 5 + rel)
        return Decoded(5, f"call {hex_u32(target)}")

    if op == 0xE9:
        if off + 5 > len(buf):
            return Decoded(1, f"db 0x{op:02X}")
        rel = read_i32_le(buf, off + 1)
        target = u32(ip + 5 + rel)
        return Decoded(5, f"jmp {hex_u32(target)}")

    if op == 0xEB:
        if off + 2 > len(buf):
            return Decoded(1, f"db 0x{op:02X}")
        rel = read_i8(buf, off + 1)
        target = u32(ip + 2 + rel)
        return Decoded(2, f"jmp {hex_u32(target)}")

    if op == 0x74:
        if off + 2 > len(buf):
            return Decoded(1, f"db 0x{op:02X}")
        rel = read_i8(buf, off + 1)
        target = u32(ip + 2 + rel)
        return Decoded(2, f"je {hex_u32(target)}")

    # 0F prefix: Jcc rel32
    if op == 0x0F:
        if off + 2 > len(buf):
            return Decoded(1, "db 0x0F")
        op2 = read_u8(buf, off + 1)
        if 0x80 <= op2 <= 0x8F:
            if off + 6 > len(buf):
                return Decoded(2, "db 0x0F")
            rel = read_i32_le(buf, off + 2)
            target = u32(ip + 6 + rel)
            mnem = jcc_mnemonic(op2)
            return Decoded(6, f"{mnem} {hex_u32(target)}")
        return Decoded(2, "db 0x0F")

    # mov r32, r/m32 (8B /r) and mov r/m32, r32 (89 /r)
    if op in (0x8B, 0x89):
        if off + 2 > len(buf):
            return Decoded(1, f"db 0x{op:02X}")
        m = decode_modrm(read_u8(buf, off + 1))
        rm_str, extra = format_rm32(buf, off + 2, m)
        length = 2 + extra

        if op == 0x8B:
            return Decoded(length, f"mov {REG32[m.reg]}, {rm_str}")
        else:
            return Decoded(length, f"mov {rm_str}, {REG32[m.reg]}")

    # FF group: /2 call r/m32, /4 jmp r/m32
    if op == 0xFF:
        if off + 2 > len(buf):
            return Decoded(1, "db 0xFF")
        m = decode_modrm(read_u8(buf, off + 1))
        rm_str, extra = format_rm32(buf, off + 2, m)
        length = 2 + extra

        if m.reg == 2:
            return Decoded(length, f"call {rm_str}")
        if m.reg == 4:
            return Decoded(length, f"jmp {rm_str}")
        return Decoded(1, "db 0xFF")

    return Decoded(1, f"db 0x{op:02X}")


def usage() -> None:
    sys.stderr.write(
        "minidism.py -i <input.bin> -a <base_addr> [--hex]\n"
        "Example: py -3 minidism.py -i ..\\test_data\\pushpop.bin -a 0x401000 --hex\n"
    )


def main(argv: list[str]) -> int:
    in_path: Optional[str] = None
    base: int = 0
    # kept for parity with other backends; output is always hex-format like expected
    _hex_on = False

    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "-i" and i + 1 < len(argv):
            in_path = argv[i + 1]
            i += 2
        elif a == "-a" and i + 1 < len(argv):
            base = parse_u32(argv[i + 1])
            i += 2
        elif a == "--hex":
            _hex_on = True
            i += 1
        elif a in ("-h", "--help"):
            usage()
            return 0
        else:
            sys.stderr.write(f"Unknown arg: {a}\n")
            usage()
            return 2

    if not in_path:
        usage()
        return 2

    try:
        data = open(in_path, "rb").read()
    except OSError as e:
        sys.stderr.write(f"Failed to open input: {in_path}\n{e}\n")
        return 2

    off = 0
    ip = base
    n = len(data)

    while off < n:
        d = decode_one(data, off, ip)
        if d.length <= 0:
            break
        length = d.length
        if off + length > n:
            length = 1

        instr_bytes = data[off:off + length]
        print_line(ip, instr_bytes, d.text)

        off += length
        ip = u32(ip + length)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
