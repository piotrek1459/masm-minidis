# MASM Mini Disassembler

> We’re building a minimal x86 (32‑bit) disassembler in MASM for Windows.

---

## Why we’re building this

- **Core assembly skills:** We parse bytes, use bitwise ops, work with tables, and implement control flow and I/O — all in MASM.
- **Manageable scope:** We constrain the scope to a subset of common x86 opcodes (e.g., `MOV`, `ADD`, `SUB`, `PUSH`, `POP`, `CALL`, `JMP`, `RET`, `INC/DEC`, `CMP`, `TEST`, `NOP`) and basic ModR/M + SIB handling, so the project stays realistic for a course deliverable.
- **Real-world relevance:** We care about this because disassembly is foundational for reverse engineering, debugging, and security tooling.
- **Extensible:** We set clear milestones so we can add more instructions or x64 support later (extra credit).

---

## Our Goals & Non‑Goals

### Our Goals
- We read a **flat 32-bit code blob** (raw `.bin`, not a PE parser) from disk.
- We disassemble from a **given base address** (for pretty printed addresses) and **decode length** bytes.
- We support a **subset of x86 opcodes** with ModR/M and simple SIB and immediate/displacement decoding.
- We output each instruction as:  
  `00401000  55                   push ebp`  
  `00401001  8BEC                 mov ebp, esp`

### Non-Goals (for v1)
- We don’t parse full PEs (no section tables/relocs).
- We don’t aim for full x86 coverage; no floating‑point, no AVX/SSE for v1.
- We don’t execute instruction semantics — we **decode only**.

---

## Command-Line Interface

```text
masm-minidis.exe -i <input.bin> [-o out.txt] [-a 0xBASE] [-n BYTES] [--hex]
```

- `-i` : input raw binary file (**required**)
- `-o` : output file (default: stdout)
- `-a` : starting address printed with each instruction (default: 0x00400000)
- `-n` : number of bytes to decode (default: entire file)
- `--hex` : also print raw bytes per instruction line

Here’s how we expect to run it.

**Example**
```powershell
masm-minidis.exe -i samples\prologue.bin -a 0x401000 --hex
```

---

## Project Structure

We organize the repository like this:

```
masm-minidis/
├─ src/
│  ├─ disasm.asm          ; program entry + CLI + main loop
│  ├─ decoder.asm         ; opcode tables + ModR/M + SIB + printers
│  ├─ tables.asm          ; opcode metadata tables
│  ├─ io.asm              ; file read, buffered output
│  └─ util.asm            ; hex printing, number parsing, helpers
├─ include/
│  ├─ macros.inc          ; handy macros (PRINT, PUTC, LOADBYTE, etc.)
│  └─ headers.inc         ; extern/proto declarations
├─ samples/
│  ├─ prologue.bin        ; bytes: 55 8B EC 83 EC 10
│  └─ movimm.bin          ; bytes: B8 78 56 34 12
├─ build/
│  └─ (out files here)
├─ tests/
│  ├─ cases.txt           ; table of inputs -> expected mnemonics
│  └─ oracle.md           ; cross-check guide (e.g., with ndisasm/objdump)
└─ README.md
```

---

## Build (Windows, MASM)

We build this with **Visual Studio Build Tools** or **Visual Studio** with MASM (`ml.exe`) on PATH.

### 32-bit build (recommended for v1)
```bat
REM From repo root
ml /c /coff /nologo /Fo:build\disasm.obj src\disasm.asm
ml /c /coff /nologo /Fo:build\decoder.obj src\decoder.asm
ml /c /coff /nologo /Fo:build\tables.obj  src\tables.asm
ml /c /coff /nologo /Fo:build\io.obj      src\io.asm
ml /c /coff /nologo /Fo:build\util.obj    src\util.asm

link /subsystem:console /nologo /out:build\masm-minidis.exe ^
  build\disasm.obj build\decoder.obj build\tables.obj build\io.obj build\util.obj
```

> For x64 later: use `ml64` and adjust calling conventions & prototypes.

---

## Implementation Plan (Step‑by‑Step)

Here’s how we plan to implement it, step by step.

### Milestone 0 — Scaffolding & I/O
1. We write an **argument parser** in `disasm.asm` supporting `-i`, `-o`, `-a`, `-n`, `--hex`.
2. We **read the file** into a buffer (e.g., `VirtualAlloc` + `ReadFile`) and store the size.
3. We implement **buffered print** routines: `print_str`, `print_hex8/16/32`, `print_byte_as_hex`, newline, space, etc.
4. We handle the **address base**: `current_addr = base + offset`.

**Deliverable:** We can read a file and print addresses/hex byte dump line per byte (no decoding yet).

---

### Milestone 1 — Minimal Decoder (No ModR/M)
We implement a loop that:
- Fetches the opcode byte at `buf+off`.
- Uses an **opcode table** (a jump table via `jmp [table + eax*4]`, or a big `cmp/jz` chain initially).
- Handles **single‑byte opcodes without ModR/M**:
  - `0x90` `NOP`
  - `0xC3` `RET`
  - `0xCC` `INT3`
  - `0x40..0x47` `INC r32`
  - `0x48..0x4F` `DEC r32`
  - `0x50..0x57` `PUSH r32`
  - `0x58..0x5F` `POP r32`
- Handles **`MOV r32, imm32`** (`0xB8..0xBF`) by reading a 4‑byte little‑endian immediate.

**Deliverable:** We correctly print a few trivial instructions with operands.

---

### Milestone 2 — ModR/M & Displacements
- We parse the **ModR/M** byte: `mod = [7:6]`, `reg = [5:3]`, `rm = [2:0]`.
- If `rm == 4` and `mod != 3`, we parse the **SIB**: `scale=[7:6]`, `index=[5:3]`, `base=[2:0]`.
- Based on `mod`, we read **disp8/disp32** if present.
- We implement **register naming** via tables (`EAX, ECX, ...` for 32‑bit).  
- We add these instructions:
  - `0x8B` `MOV r32, r/m32`
  - `0x89` `MOV r/m32, r32`
  - `0x03` `ADD r32, r/m32`
  - `0x2B` `SUB r32, r/m32`
  - `0x85` `TEST r/m32, r32` (uses `reg` field)
  - Group opcodes via `/digit` in `reg` field (e.g., `0x81 /0 ADD imm32 to r/m32`, `/5 SUB`, `/7 CMP`).

**Deliverable:** We produce correct r/m decoding with addressing forms like `[EAX]`, `[EBX+4]`, `[EAX+ECX*4+0x10]`.

---

### Milestone 3 — Control Flow & Immediates
- We implement **relative jumps/calls**:
  - `0xE8` `CALL rel32` (we print target = `addr_next + signext(rel32)`)
  - `0xE9` `JMP rel32`
  - `0xEB` `JMP rel8`
  - Conditional jumps (short) `0x70..0x7F` (`JO, JNO, JB, JAE, JE, JNE, ...`)
- We add **`PUSH imm8/imm32`** (`0x6A`/`0x68`).

**Deliverable:** We print correct target addresses for relative control flow.

---

### Milestone 4 — Polish & Robustness
- We pretty‑print the **byte dump** per instruction when `--hex` is set (collect N bytes until next off).
- We add **bounds checks** so we don’t read past the end; we print `db 0x??` for unknown/incomplete bytes.
- For **unknown opcodes**, we emit a `db` line and advance by 1 byte.
- We maintain a **test corpus** under `samples/` and `tests/` with expected outputs.

---

## Data Structures & Tables

We use these structures and tables:

- **Register tables (r32)**: `EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI`.
- **Opcode descriptor** (per opcode): flags: needs ModR/M, has imm8/imm32, is group `/digit`, mnemonic id.
- **Mnemonic strings** table: `"mov", "add", "sub", "push", "pop", "call", "jmp", "ret", ...`.
- **Formatter**: builds operand strings (`r32`, `[base + index*scale + disp]`, `imm32`) into a print buffer.

---

## Example

Input bytes (`samples\prologue.bin`): `55 8B EC 83 EC 10`  
Base address: `0x00401000`

Expected output (with `--hex`):
```
00401000  55                 push ebp
00401001  8B EC              mov  ebp, esp
00401003  83 EC 10           sub  esp, 0x10
```

Input bytes (`samples\movimm.bin`): `B8 78 56 34 12`  
```
00402000  B8 78 56 34 12     mov  eax, 0x12345678
```

---

## Testing Strategy

- We keep **golden samples** in `samples/` with expected disassembly in `tests/cases.txt`.
- We cross‑check a few buffers using another disassembler (e.g., `ndisasm -b32` or `objdump -D`) and paste the **expected** result (no runtime dependency).
- We do light fuzzing: random bytes → ensure no crash; only `db` on unknowns/incomplete.

---

## Stretch Goals (Optional)
- If we have time, we’d like to:
  - Add **x64 mode** (`ml64`): new registers, RIP‑relative addressing, different calling convention.
  - Handle **prefixes**: `0x66`, `0x67`, `0xF3` — minimal operand/address‑size override support.
  - Build a **PE `.text` extractor**: read a PE and disassemble only the `.text` section.
  - Add **colorized output** and symbol maps.
  - Expand **opcode coverage** and add two‑byte opcodes (`0x0F` prefix).

---

## Academic Integrity & Sources
- We implement from the **Intel® 64 and IA‑32 Architectures Software Developer’s Manual** and our course notes.
- We cite any external snippets we adapt. We keep our implementation original.

---

## Our Checklist
- [ ] CLI args parsed
- [ ] File read into memory
- [ ] Hex/addr printers
- [ ] Opcode table + trivial opcodes
- [ ] ModR/M + SIB + displacements
- [ ] Control-flow (rel8/rel32, call/jmp/jcc)
- [ ] Tests & samples
- [ ] README updated with coverage

---

## License
MIT
