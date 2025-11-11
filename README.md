# MASM Mini Disassembler (C + MASM, Win32)

> A minimal **x86 (32-bit)** disassembler for Windows — algorithms written in **MASM**, program logic and CLI in **C**.  
> Built and tested with **Visual Studio 2022** on **Windows 11**.

---

## 💡 Why we’re building this
- **Learn real assembly:** decoding bytes, handling ModR/M + SIB, working with immediates and displacements.
- **Practical value:** disassembly is fundamental in debugging, reverse engineering, and malware analysis.
- **Manageable scope:** only a useful subset of x86 32-bit instructions → realistic academic project.
- **Extensible:** the modular C ↔ ASM design allows more instructions or x64 mode later.

---

## 🎯 Goals
- Read a **flat 32-bit binary blob** (not a PE parser).
- Decode instructions from a **base address** and print mnemonic + operands.
- Support common x86 opcodes with **ModR/M + SIB**.
- Output example:
```
00401000 55 push ebp
00401001 8B EC mov ebp, esp
```

### 🚫 Non-Goals (v1)
- No full PE parsing.
- No FP/SSE/AVX.
- No execution — decoding only.

---

## ⚙️ Command-Line Interface
```text
minidism.exe -i <input.bin> [-o out.txt] [-a 0xBASE] [-n BYTES] [--hex]
```
| Option  | Description                                           |
| ------- | ----------------------------------------------------- |
| `-i`    | input raw binary file (**required**)                  |
| `-o`    | output file (default stdout)                          |
| `-a`    | base address for printed offsets (default 0x00400000) |
| `-n`    | max bytes to decode                                   |
| `--hex` | also print raw bytes per instruction                  |

## Example
```
minidism.exe -i samples\prologue.bin -a 0x401000 --hex
```
## Repository Structure
```
masm-minidis/
├─ minidism/              # Visual Studio project
│  ├─ minidism.sln
│  ├─ main.c              # CLI + decode loop
│  ├─ format.c            # address / hex formatting
│  ├─ decoder.asm         # decode_one PROC C – algorithms in MASM
│  ├─ tables.asm          # opcode / register tables (TBD)
│  ├─ util.asm            # helper routines (TBD)
│  ├─ decoder.h, format.h
│  └─ (Debug / Release ignored by .gitignore)
├─ samples/
│  └─ test.bin            # demo bytes (90 C3)
├─ ProjectCardAPL.pdf
├─ .gitignore
└─ README.md
```

## 🛠 Building & Running on Your Machine (Windows 11)

**1️⃣ Clone the Repository**
```
git clone https://github.com/piotrek1459/masm-minidis.git
cd masm-minidis
```
**2️⃣ Open in Visual Studio 2022**

- Double-click minidism\minidism.sln.

- Ensure Desktop development with C++ workload is installed
(Tools → Get Tools and Features…).

- Enable MASM: Project → Build Dependencies → Build Customizations… → ✔️ masm.

- Build → Configuration Manager → Platform → select x86 (Win32).

- Rebuild Solution.

**3️⃣ Create a Test Binary**
In PowerShell inside minidism/:
```
[byte[]]$b = 0x90,0xC3   # NOP + RET
Set-Content -Path test.bin -Value $b -Encoding Byte
```

**4️⃣ Run the Program**
In VS:
Project → Properties → Debugging → Command Arguments:
```
-i "$(ProjectDir)test.bin" -a 0x401000 --hex
```
Then F5 → Start Debugging
Expected output:
```
00401000:  90            nop
00401001:  C3            ret
```

(You can also run from terminal:)
```
cd minidism\Debug
.\minidism.exe -i ..\test.bin -a 0x401000 --hex
```

## 🧩 Implementation Roadmap
| Milestone | Description                                | Deliverable            |
| --------- | ------------------------------------------ | ---------------------- |
| **M0**    | C ↔ ASM scaffolding, I/O, printing         | runs, prints `db 0x??` |
| **M1**    | single-byte opcodes (`nop`, `ret`, `int3`) | decoded text           |
| **M1.5**  | `push/pop r32`, `mov r32, imm32`           | reg/immediate operands |
| **M2**    | ModR/M + SIB + displacements               | full r/m addressing    |
| **M3**    | control-flow (`call`, `jmp`, `jcc`)        | relative targets       |
| **M4**    | polish + bounds checks + tests             | release candidate      |

## 🧠 Testing & Validation
- Keep canonical .bin samples in samples/.

- Mirror expected output in tests/cases.txt.

- Cross-check with ndisasm -b32 or objdump -D.

- Random-byte fuzz → must not crash; only emit db.