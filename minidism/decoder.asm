option casemap:none
.386
.model flat, c
.stack 4096

PUBLIC decoder_init
PUBLIC decode_one

.data
; small string literals
sz_nop     db "nop",0
sz_ret     db "ret",0
sz_int3    db "int3",0

.code

; ---------------------------------------------------------
; void __cdecl decoder_init(void);
decoder_init PROC C
    ret
decoder_init ENDP

; ---------------------------------------------------------
; int __cdecl decode_one(const uint8_t* buf,int len,int off,uint32_t base,
;                        char* out,int outcap,int hexOn)
decode_one PROC C pBuf:PTR BYTE, len:DWORD, off:DWORD, base:DWORD, pOut:PTR BYTE, outcap:DWORD, hexOn:DWORD
    push    ebx
    push    esi
    push    edi

    ; EDI = out buffer
    mov     edi, pOut
    mov     ecx, outcap
    cmp     ecx, 1
    jae     have_space
    xor     eax, eax
    jmp     epilogue
have_space:
    mov     byte ptr [edi], 0

    ; ESI = buf + off
    mov     esi, pBuf
    add     esi, off

    ; IMPORTANT: in your harness, 'len' is already remaining bytes
    mov     eax, len
    cmp     eax, 1
    jl      unknown

    ; opcode
    movzx   eax, byte ptr [esi]
    mov     bl, al

    ; ---- 0F xx (two-byte opcodes) ----
    cmp     bl, 00Fh
    je      do_0f_prefix

    ; ---- simple one-byte ----
    cmp     bl, 090h
    je      do_nop
    cmp     bl, 0C3h
    je      do_ret
    cmp     bl, 0CCh
    je      do_int3

    ; ---- Control flow ----
    cmp     bl, 0E8h
    je      do_call_rel32
    cmp     bl, 0E9h
    je      do_jmp_rel32
    cmp     bl, 0EBh
    je      do_jmp_rel8

    ; FF group (call/jmp r/m32)
    cmp     bl, 0FFh
    je      do_ff_group

    ; Jcc rel8 (70..7F)
    cmp     bl, 070h
    jb      after_jcc8
    cmp     bl, 07Fh
    jbe     do_jcc_rel8
after_jcc8:

    ; ---- PUSH/POP r32 (50..5F) ----
    cmp     bl, 050h
    jb      check_mov_imm
    cmp     bl, 057h
    jbe     do_push
    cmp     bl, 058h
    jb      check_mov_imm
    ; ---- MOV r32, r/m32  (8B /r) ----
    cmp     bl, 08Bh
    je      do_mov_r_rm

    ; ---- MOV r/m32, r32  (89 /r) ----
    cmp     bl, 089h
    je      do_mov_rm_r

    cmp     bl, 05Fh
    jbe     do_pop

check_mov_imm:
    ; ---- MOV r32, imm32 (B8..BF) ----
    cmp     bl, 0B8h
    jb      unknown
    cmp     bl, 0BFh
    ja      unknown

    ; need 5 bytes total (remaining)
    mov     eax, len
    cmp     eax, 5
    jl      unknown

    ; write "mov "
    mov     byte ptr [edi+0], 'm'
    mov     byte ptr [edi+1], 'o'
    mov     byte ptr [edi+2], 'v'
    mov     byte ptr [edi+3], ' '
    add     edi, 4

    ; r = opcode - B8
    movzx   eax, bl
    sub     eax, 0B8h     ; 0..7

    ; write reg name (3 chars)
    call    write_reg3

    ; write ", 0x"
    mov     byte  ptr [edi], ','
    mov     byte  ptr [edi+1], ' '
    add     edi, 2
    mov     byte  ptr [edi], '0'
    mov     byte  ptr [edi+1], 'x'
    add     edi, 2

    ; imm32 from [esi+1]
    mov     eax, dword ptr [esi+1]

    ; write 8 hex nibbles (MSB→LSB)
    mov     ecx, 8
hex_loop:
    mov     edx, eax
    and     edx, 0F0000000h
    shr     edx, 28
    cmp     edx, 10
    jb      hex_digit
    add     dl, 'A' - 10
    jmp     short hex_store
hex_digit:
    add     dl, '0'
hex_store:
    mov     [edi], dl
    inc     edi
    shl     eax, 4
    dec     ecx
    jnz     hex_loop

    ; NUL
    mov     byte ptr [edi], 0
    mov     eax, 5
    jmp     epilogue

do_push:
    ; write "push "
    mov     byte ptr [edi+0], 'p'
    mov     byte ptr [edi+1], 'u'
    mov     byte ptr [edi+2], 's'
    mov     byte ptr [edi+3], 'h'
    mov     byte ptr [edi+4], ' '
    add     edi, 5

    ; reg = opcode - 50h
    movzx   eax, bl
    sub     eax, 050h
    call    write_reg3

    mov     byte ptr [edi], 0
    mov     eax, 1
    jmp     epilogue

do_pop:
    ; write "pop "
    mov     byte ptr [edi+0], 'p'
    mov     byte ptr [edi+1], 'o'
    mov     byte ptr [edi+2], 'p'
    mov     byte ptr [edi+3], ' '
    add     edi, 4

    ; reg = opcode - 58h
    movzx   eax, bl
    sub     eax, 058h
    call    write_reg3

    mov     byte ptr [edi], 0
    mov     eax, 1
    jmp     epilogue



do_call_rel32:
    mov     eax, len
    cmp     eax, 5
    jl      unknown

    ; "call "
    mov     byte ptr [edi+0], 'c'
    mov     byte ptr [edi+1], 'a'
    mov     byte ptr [edi+2], 'l'
    mov     byte ptr [edi+3], 'l'
    mov     byte ptr [edi+4], ' '
    add     edi, 5

    ; target = base + off + 5 + rel32
    mov     eax, base
    add     eax, off
    add     eax, 5
    add     eax, dword ptr [esi+1]

    mov     byte ptr [edi], '0'
    mov     byte ptr [edi+1], 'x'
    add     edi, 2
    call    write_hex32

    mov     byte ptr [edi], 0
    mov     eax, 5
    jmp     epilogue

do_jmp_rel32:
    mov     eax, len
    cmp     eax, 5
    jl      unknown

    ; "jmp "
    mov     byte ptr [edi+0], 'j'
    mov     byte ptr [edi+1], 'm'
    mov     byte ptr [edi+2], 'p'
    mov     byte ptr [edi+3], ' '
    add     edi, 4

    ; target = base + off + 5 + rel32
    mov     eax, base
    add     eax, off
    add     eax, 5
    add     eax, dword ptr [esi+1]

    mov     byte ptr [edi], '0'
    mov     byte ptr [edi+1], 'x'
    add     edi, 2
    call    write_hex32

    mov     byte ptr [edi], 0
    mov     eax, 5
    jmp     epilogue

do_jmp_rel8:
    mov     eax, len
    cmp     eax, 2
    jl      unknown

    ; "jmp "
    mov     byte ptr [edi+0], 'j'
    mov     byte ptr [edi+1], 'm'
    mov     byte ptr [edi+2], 'p'
    mov     byte ptr [edi+3], ' '
    add     edi, 4

    ; rel8 signed
    movsx   edx, byte ptr [esi+1]
    mov     eax, base
    add     eax, off
    add     eax, 2
    add     eax, edx

    mov     byte ptr [edi], '0'
    mov     byte ptr [edi+1], 'x'
    add     edi, 2
    call    write_hex32

    mov     byte ptr [edi], 0
    mov     eax, 2
    jmp     epilogue


; ---------------------------------------------------------
; 0F xx prefix handling (two-byte opcodes)
; Currently supports: 0F 80..8F  Jcc rel32
; ---------------------------------------------------------
do_0f_prefix:
    mov     eax, len
    cmp     eax, 2
    jl      unknown

    movzx   eax, byte ptr [esi+1]
    mov     bl, al

    ; 0F 80..8F => Jcc rel32
    cmp     bl, 080h
    jb      unknown
    cmp     bl, 08Fh
    jbe     do_jcc_rel32
    jmp     unknown


do_jcc_rel32:
    mov     eax, len
    cmp     eax, 6
    jl      unknown

    ; write "j?? " (same condition mapping as rel8)
    movzx   eax, bl
    and     eax, 0Fh

    mov     byte ptr [edi+0], 'j'
    cmp     eax, 0
    je      cc32_jo
    cmp     eax, 1
    je      cc32_jno
    cmp     eax, 2
    je      cc32_jb
    cmp     eax, 3
    je      cc32_jae
    cmp     eax, 4
    je      cc32_je
    cmp     eax, 5
    je      cc32_jne
    cmp     eax, 6
    je      cc32_jbe
    cmp     eax, 7
    je      cc32_ja
    cmp     eax, 8
    je      cc32_js
    cmp     eax, 9
    je      cc32_jns
    cmp     eax, 0Ah
    je      cc32_jp
    cmp     eax, 0Bh
    je      cc32_jnp
    cmp     eax, 0Ch
    je      cc32_jl
    cmp     eax, 0Dh
    je      cc32_jge
    cmp     eax, 0Eh
    je      cc32_jle
    jmp     cc32_jg

cc32_jo:
    mov     byte ptr [edi+1], 'o'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc32_done
cc32_jno:
    mov     byte ptr [edi+1], 'n'
    mov     byte ptr [edi+2], 'o'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc32_done
cc32_jb:
    mov     byte ptr [edi+1], 'b'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc32_done
cc32_jae:
    mov     byte ptr [edi+1], 'a'
    mov     byte ptr [edi+2], 'e'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc32_done
cc32_je:
    mov     byte ptr [edi+1], 'e'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc32_done
cc32_jne:
    mov     byte ptr [edi+1], 'n'
    mov     byte ptr [edi+2], 'e'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc32_done
cc32_jbe:
    mov     byte ptr [edi+1], 'b'
    mov     byte ptr [edi+2], 'e'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc32_done
cc32_ja:
    mov     byte ptr [edi+1], 'a'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc32_done
cc32_js:
    mov     byte ptr [edi+1], 's'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc32_done
cc32_jns:
    mov     byte ptr [edi+1], 'n'
    mov     byte ptr [edi+2], 's'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc32_done
cc32_jp:
    mov     byte ptr [edi+1], 'p'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc32_done
cc32_jnp:
    mov     byte ptr [edi+1], 'n'
    mov     byte ptr [edi+2], 'p'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc32_done
cc32_jl:
    mov     byte ptr [edi+1], 'l'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc32_done
cc32_jge:
    mov     byte ptr [edi+1], 'g'
    mov     byte ptr [edi+2], 'e'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc32_done
cc32_jle:
    mov     byte ptr [edi+1], 'l'
    mov     byte ptr [edi+2], 'e'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc32_done
cc32_jg:
    mov     byte ptr [edi+1], 'g'
    mov     byte ptr [edi+2], ' '
    add     edi, 3

cc32_done:
    ; target = base + off + 6 + rel32
    mov     eax, base
    add     eax, off
    add     eax, 6
    add     eax, dword ptr [esi+2]

    mov     byte ptr [edi], '0'
    mov     byte ptr [edi+1], 'x'
    add     edi, 2
    call    write_hex32

    mov     byte ptr [edi], 0
    mov     eax, 6
    jmp     epilogue


; ---------------------------------------------------------
; FF /2 call r/m32
; FF /4 jmp  r/m32
; ---------------------------------------------------------
do_ff_group:
    mov     eax, len
    cmp     eax, 2
    jl      unknown

    movzx   eax, byte ptr [esi+1]
    shr     eax, 3
    and     eax, 7

    cmp     eax, 2
    je      ff_call
    cmp     eax, 4
    je      ff_jmp
    jmp     unknown

ff_call:
    ; "call "
    mov     byte ptr [edi+0], 'c'
    mov     byte ptr [edi+1], 'a'
    mov     byte ptr [edi+2], 'l'
    mov     byte ptr [edi+3], 'l'
    mov     byte ptr [edi+4], ' '
    add     edi, 5
    jmp     ff_emit_rm

ff_jmp:
    ; "jmp "
    mov     byte ptr [edi+0], 'j'
    mov     byte ptr [edi+1], 'm'
    mov     byte ptr [edi+2], 'p'
    mov     byte ptr [edi+3], ' '
    add     edi, 4

ff_emit_rm:
    push    esi
    lea     esi, [esi+1]
    call    write_rm32
    mov     ebx, eax
    pop     esi

    mov     byte ptr [edi], 0
    mov     eax, ebx
    inc     eax
    jmp     epilogue

do_jcc_rel8:
    mov     eax, len
    cmp     eax, 2
    jl      unknown

    ; write "j?? "
    ; condition = opcode low nibble
    movzx   eax, bl
    and     eax, 0Fh

    ; default: "j??"
    mov     byte ptr [edi+0], 'j'
    ; choose mnemonic
    cmp     eax, 0
    je      cc_jo
    cmp     eax, 1
    je      cc_jno
    cmp     eax, 2
    je      cc_jb
    cmp     eax, 3
    je      cc_jae
    cmp     eax, 4
    je      cc_je
    cmp     eax, 5
    je      cc_jne
    cmp     eax, 6
    je      cc_jbe
    cmp     eax, 7
    je      cc_ja
    cmp     eax, 8
    je      cc_js
    cmp     eax, 9
    je      cc_jns
    cmp     eax, 0Ah
    je      cc_jp
    cmp     eax, 0Bh
    je      cc_jnp
    cmp     eax, 0Ch
    je      cc_jl
    cmp     eax, 0Dh
    je      cc_jge
    cmp     eax, 0Eh
    je      cc_jle
    ; else 0F -> jg
    jmp     cc_jg

cc_jo:
    mov     byte ptr [edi+1], 'o'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc_done
cc_jno:
    mov     byte ptr [edi+1], 'n'
    mov     byte ptr [edi+2], 'o'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc_done
cc_jb:
    mov     byte ptr [edi+1], 'b'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc_done
cc_jae:
    mov     byte ptr [edi+1], 'a'
    mov     byte ptr [edi+2], 'e'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc_done
cc_je:
    mov     byte ptr [edi+1], 'e'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc_done
cc_jne:
    mov     byte ptr [edi+1], 'n'
    mov     byte ptr [edi+2], 'e'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc_done
cc_jbe:
    mov     byte ptr [edi+1], 'b'
    mov     byte ptr [edi+2], 'e'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc_done
cc_ja:
    mov     byte ptr [edi+1], 'a'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc_done
cc_js:
    mov     byte ptr [edi+1], 's'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc_done
cc_jns:
    mov     byte ptr [edi+1], 'n'
    mov     byte ptr [edi+2], 's'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc_done
cc_jp:
    mov     byte ptr [edi+1], 'p'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc_done
cc_jnp:
    mov     byte ptr [edi+1], 'n'
    mov     byte ptr [edi+2], 'p'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc_done
cc_jl:
    mov     byte ptr [edi+1], 'l'
    mov     byte ptr [edi+2], ' '
    add     edi, 3
    jmp     cc_done
cc_jge:
    mov     byte ptr [edi+1], 'g'
    mov     byte ptr [edi+2], 'e'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc_done
cc_jle:
    mov     byte ptr [edi+1], 'l'
    mov     byte ptr [edi+2], 'e'
    mov     byte ptr [edi+3], ' '
    add     edi, 4
    jmp     cc_done
cc_jg:
    mov     byte ptr [edi+1], 'g'
    mov     byte ptr [edi+2], ' '
    add     edi, 3

cc_done:
    ; compute target
    movsx   edx, byte ptr [esi+1]
    mov     eax, base
    add     eax, off
    add     eax, 2
    add     eax, edx

    mov     byte ptr [edi], '0'
    mov     byte ptr [edi+1], 'x'
    add     edi, 2
    call    write_hex32

    mov     byte ptr [edi], 0
    mov     eax, 2
    jmp     epilogue

do_mov_r_rm:
    ; need at least opcode + modrm
    mov     eax, len
    cmp     eax, 2
    jl      unknown

    ; write "mov "
    mov     byte ptr [edi+0], 'm'
    mov     byte ptr [edi+1], 'o'
    mov     byte ptr [edi+2], 'v'
    mov     byte ptr [edi+3], ' '
    add     edi, 4

    ; modrm at [opcode+1]
    movzx   eax, byte ptr [esi+1]
    shr     eax, 3
    and     eax, 7
    call    write_reg3

    ; write ", "
    mov     byte ptr [edi], ','
    mov     byte ptr [edi+1], ' '
    add     edi, 2

    ; write r/m32 operand from modrm stream
    push    esi
    lea     esi, [esi+1]
    call    write_rm32
    mov     ebx, eax        ; bytes used after opcode
    pop     esi

    mov     byte ptr [edi], 0
    mov     eax, ebx
    inc     eax             ; include opcode byte
    jmp     epilogue

do_mov_rm_r:
    ; need at least opcode + modrm
    mov     eax, len
    cmp     eax, 2
    jl      unknown

    ; write "mov "
    mov     byte ptr [edi+0], 'm'
    mov     byte ptr [edi+1], 'o'
    mov     byte ptr [edi+2], 'v'
    mov     byte ptr [edi+3], ' '
    add     edi, 4

    ; dest = r/m32 operand
    push    esi
    lea     esi, [esi+1]
    call    write_rm32
    mov     ebx, eax        ; bytes used after opcode
    pop     esi

    ; write ", "
    mov     byte ptr [edi], ','
    mov     byte ptr [edi+1], ' '
    add     edi, 2

    ; src reg = reg field from modrm
    movzx   eax, byte ptr [esi+1]
    shr     eax, 3
    and     eax, 7
    call    write_reg3

    mov     byte ptr [edi], 0
    mov     eax, ebx
    inc     eax
    jmp     epilogue


do_nop:
    lea     esi, sz_nop
copy_nop:
    mov     al, [esi]
    mov     [edi], al
    inc     esi
    inc     edi
    cmp     al, 0
    jne     copy_nop
    mov     eax, 1
    jmp     epilogue

do_ret:
    lea     esi, sz_ret
copy_ret:
    mov     al, [esi]
    mov     [edi], al
    inc     esi
    inc     edi
    cmp     al, 0
    jne     copy_ret
    mov     eax, 1
    jmp     epilogue

do_int3:
    lea     esi, sz_int3
copy_int3:
    mov     al, [esi]
    mov     [edi], al
    inc     esi
    inc     edi
    cmp     al, 0
    jne     copy_int3
    mov     eax, 1
    jmp     epilogue

unknown:
    xor     eax, eax

epilogue:
    pop     edi
    pop     esi
    pop     ebx
    ret
decode_one ENDP

; ------------------------------------------------------------
; write_hex8
; IN:  AL = byte value
;      EDI = output cursor
; OUT: writes 2 hex digits (uppercase), advances EDI by 2
; ------------------------------------------------------------
write_hex8 PROC
    push eax
    push edx

    mov dl, al
    shr dl, 4
    and dl, 0Fh
    cmp dl, 10
    jb  wh8_hi_digit
    add dl, 'A' - 10
    jmp short wh8_hi_store
wh8_hi_digit:
    add dl, '0'
wh8_hi_store:
    mov [edi], dl
    inc edi

    pop edx
    push edx

    mov dl, al
    and dl, 0Fh
    cmp dl, 10
    jb  wh8_lo_digit
    add dl, 'A' - 10
    jmp short wh8_lo_store
wh8_lo_digit:
    add dl, '0'
wh8_lo_store:
    mov [edi], dl
    inc edi

    pop edx
    pop eax
    ret
write_hex8 ENDP

; ------------------------------------------------------------
; write_hex32
; IN:  EAX = dword value
;      EDI = output cursor
; OUT: writes 8 hex digits (uppercase), advances EDI by 8
; ------------------------------------------------------------
write_hex32 PROC
    push ecx
    push edx

    mov ecx, 8
wh32_loop:
    mov edx, eax
    and edx, 0F0000000h
    shr edx, 28
    cmp edx, 10
    jb  wh32_digit
    add dl, 'A' - 10
    jmp short wh32_store
wh32_digit:
    add dl, '0'
wh32_store:
    mov [edi], dl
    inc edi
    shl eax, 4
    dec ecx
    jnz wh32_loop

    pop edx
    pop ecx
    ret
write_hex32 ENDP


; ------------------------------------------------------------
; write_rm32
; IN:  ESI = pointer to ModR/M byte
;      EDI = output cursor
; OUT: EAX = bytes consumed from ModR/M stream (>=1)
;      EDI advanced
; Supports 32-bit addressing with optional SIB + disp8/disp32
; ------------------------------------------------------------
write_rm32 PROC
    ; We'll use a small stack frame to keep values stable.
    ; Locals (DWORD):
    ; [ebp-4]  = base (0..7) or 0xFFFFFFFF for "no base"
    ; [ebp-8]  = index (0..7) or 0xFFFFFFFF for "no index"
    ; [ebp-12] = scale (0..3)
    ; [ebp-16] = disp_size (0/1/4)
    ; [ebp-20] = bytes_used (>=1)

    push    ebp
    mov     ebp, esp
    sub     esp, 20

    push    ebx
    push    ecx
    push    edx
    push    esi

    ; defaults
    mov     dword ptr [ebp-4],  0FFFFFFFFh   ; base = none
    mov     dword ptr [ebp-8],  0FFFFFFFFh   ; index = none
    mov     dword ptr [ebp-12], 0            ; scale = 0
    mov     dword ptr [ebp-16], 0            ; disp_size = 0
    mov     dword ptr [ebp-20], 1            ; bytes_used = 1 (ModR/M)

    ; read modrm
    movzx   eax, byte ptr [esi]
    mov     ebx, eax               ; keep modrm in BL

    ; mod = (modrm >> 6) & 3
    mov     ecx, eax
    shr     ecx, 6
    and     ecx, 3                 ; ECX = mod (0..3)

    ; rm  = modrm & 7
    mov     edx, eax
    and     edx, 7                 ; EDX = rm (0..7)

    ; mod==3 => register operand (rm)
    cmp     ecx, 3
    jne     wrm_mem

    mov     eax, edx
    call    write_reg3
    mov     eax, 1                 ; consumed 1 byte (ModR/M)
    jmp     wrm_done_reg

wrm_mem:
    ; write '['
    mov     byte ptr [edi], '['
    inc     edi

    ; Check if SIB present (rm==4)
    cmp     edx, 4
    jne     wrm_no_sib

    ; read SIB at [esi+1]
    movzx   eax, byte ptr [esi+1]
    ; bytes_used++
    mov     edx, dword ptr [ebp-20]
    inc     edx
    mov     dword ptr [ebp-20], edx

    ; scale = (sib >> 6) & 3
    mov     ecx, eax
    shr     ecx, 6
    and     ecx, 3
    mov     dword ptr [ebp-12], ecx

    ; index = (sib >> 3) & 7  (4 means none)
    mov     ecx, eax
    shr     ecx, 3
    and     ecx, 7
    cmp     ecx, 4
    je      wrm_idx_none
    mov     dword ptr [ebp-8], ecx
wrm_idx_none:

    ; base = sib & 7 (may become none when mod=0 and base==5)
    mov     ecx, eax
    and     ecx, 7
    mov     dword ptr [ebp-4], ecx

    jmp     wrm_after_base_index

wrm_no_sib:
    ; no SIB: base = rm
    mov     dword ptr [ebp-4], edx
    ; index stays none, scale stays 0

wrm_after_base_index:

    ; disp_size by mod
    ; mod in ECX currently? not guaranteed; recompute mod quickly
    movzx   eax, byte ptr [esi]
    mov     ecx, eax
    shr     ecx, 6
    and     ecx, 3                 ; ECX = mod

    cmp     ecx, 1
    jne     wrm_check_mod2
    mov     dword ptr [ebp-16], 1
    jmp     wrm_check_special
wrm_check_mod2:
    cmp     ecx, 2
    jne     wrm_check_special
    mov     dword ptr [ebp-16], 4

wrm_check_special:
    ; Special mod==0 cases that force disp32 and remove base:
    ; 1) no SIB and rm==5  -> [disp32]
    ; 2) SIB present and base==5 -> [index*scale + disp32]
    movzx   eax, byte ptr [esi]
    mov     ecx, eax
    shr     ecx, 6
    and     ecx, 3                 ; ECX = mod
    cmp     ecx, 0
    jne     wrm_emit

    ; rm = modrm & 7
    mov     ecx, eax
    and     ecx, 7

    cmp     ecx, 5
    jne     wrm_check_sib_base5
    ; rm==5 and mod==0 => disp32 only (no base), if no SIB
    ; If rm==5 then SIB is not present anyway.
    mov     dword ptr [ebp-16], 4
    mov     dword ptr [ebp-4], 0FFFFFFFFh
    jmp     wrm_emit

wrm_check_sib_base5:
    cmp     ecx, 4
    jne     wrm_emit               ; no SIB
    ; SIB present: if base==5 then disp32-only and no base
    mov     eax, dword ptr [ebp-4]
    cmp     eax, 5
    jne     wrm_emit
    mov     dword ptr [ebp-16], 4
    mov     dword ptr [ebp-4], 0FFFFFFFFh

wrm_emit:
    ; printed flag in BL (0/1)
    xor     ebx, ebx               ; BL=0 printed

    ; emit base if present
    mov     eax, dword ptr [ebp-4]
    cmp     eax, 0FFFFFFFFh
    je      wrm_emit_index

    call    write_reg3
    mov     bl, 1

wrm_emit_index:
    mov     eax, dword ptr [ebp-8]
    cmp     eax, 0FFFFFFFFh
    je      wrm_emit_disp

    cmp     bl, 0
    je      wrm_idx_no_plus
    mov     byte ptr [edi], '+'
    inc     edi
wrm_idx_no_plus:

    call    write_reg3
    mov     bl, 1

    ; emit scale if != 0
    mov     eax, dword ptr [ebp-12]
    test    eax, eax
    jz      wrm_emit_disp

    mov     byte ptr [edi], '*'
    inc     edi
    cmp     eax, 1
    jne     wrm_scale4
    mov     byte ptr [edi], '2'
    inc     edi
    jmp     wrm_emit_disp
wrm_scale4:
    cmp     eax, 2
    jne     wrm_scale8
    mov     byte ptr [edi], '4'
    inc     edi
    jmp     wrm_emit_disp
wrm_scale8:
    mov     byte ptr [edi], '8'
    inc     edi

wrm_emit_disp:
    mov     eax, dword ptr [ebp-16]    ; disp_size
    test    eax, eax
    jz      wrm_close

    ; disp pointer = esi + bytes_used
    mov     ecx, dword ptr [ebp-20]
    lea     ecx, [esi+ecx]

    ; read disp into EDX (signed for disp8)
    cmp     eax, 1
    jne     wrm_read_disp32
    movsx   edx, byte ptr [ecx]
    jmp     wrm_disp_loaded
wrm_read_disp32:
    mov     edx, dword ptr [ecx]
wrm_disp_loaded:

    ; If nothing printed yet -> absolute form [0x12345678]
    cmp     bl, 0
    jne     wrm_signed_disp

    mov     byte ptr [edi], '0'
    mov     byte ptr [edi+1], 'x'
    add     edi, 2
    mov     eax, edx
    call    write_hex32
    jmp     wrm_add_disp_len

wrm_signed_disp:
    test    edx, edx
    jz      wrm_add_disp_len

    jns     wrm_disp_pos
    mov     byte ptr [edi], '-'
    inc     edi
    neg     edx
    jmp     wrm_disp_emit_mag
wrm_disp_pos:
    mov     byte ptr [edi], '+'
    inc     edi

wrm_disp_emit_mag:
    mov     byte ptr [edi], '0'
    mov     byte ptr [edi+1], 'x'
    add     edi, 2

    mov     eax, dword ptr [ebp-16]    ; disp_size
    cmp     eax, 1
    jne     wrm_emit_disp32
    mov     al, dl
    call    write_hex8
    jmp     wrm_add_disp_len
wrm_emit_disp32:
    mov     eax, edx
    call    write_hex32

wrm_add_disp_len:
    ; bytes_used += disp_size
    mov     eax, dword ptr [ebp-20]
    add     eax, dword ptr [ebp-16]
    mov     dword ptr [ebp-20], eax

wrm_close:
    mov     byte ptr [edi], ']'
    inc     edi

    mov     eax, dword ptr [ebp-20]    ; return bytes_used

wrm_done_reg:
    ; restore
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx

    mov     esp, ebp
    pop     ebp
    ret
write_rm32 ENDP





; ------------------------------------------------------------
; write_reg3
; IN:  EAX = reg index 0..7
;      EDI = output cursor
; OUT: writes eax/ecx/edx/ebx/esp/ebp/esi/edi (3 chars)
;      advances EDI by 3
; NOTE: preserves EAX
; ------------------------------------------------------------
write_reg3 PROC
    push eax

    cmp     eax, 0
    je      wr_eax
    cmp     eax, 1
    je      wr_ecx
    cmp     eax, 2
    je      wr_edx
    cmp     eax, 3
    je      wr_ebx
    cmp     eax, 4
    je      wr_esp
    cmp     eax, 5
    je      wr_ebp
    cmp     eax, 6
    je      wr_esi
    jmp     wr_edi

wr_eax:
    mov     byte ptr [edi], 'e'
    mov     byte ptr [edi+1], 'a'
    mov     byte ptr [edi+2], 'x'
    add     edi, 3
    jmp     wr_done
wr_ecx:
    mov     byte ptr [edi], 'e'
    mov     byte ptr [edi+1], 'c'
    mov     byte ptr [edi+2], 'x'
    add     edi, 3
    jmp     wr_done
wr_edx:
    mov     byte ptr [edi], 'e'
    mov     byte ptr [edi+1], 'd'
    mov     byte ptr [edi+2], 'x'
    add     edi, 3
    jmp     wr_done
wr_ebx:
    mov     byte ptr [edi], 'e'
    mov     byte ptr [edi+1], 'b'
    mov     byte ptr [edi+2], 'x'
    add     edi, 3
    jmp     wr_done
wr_esp:
    mov     byte ptr [edi], 'e'
    mov     byte ptr [edi+1], 's'
    mov     byte ptr [edi+2], 'p'
    add     edi, 3
    jmp     wr_done
wr_ebp:
    mov     byte ptr [edi], 'e'
    mov     byte ptr [edi+1], 'b'
    mov     byte ptr [edi+2], 'p'
    add     edi, 3
    jmp     wr_done
wr_esi:
    mov     byte ptr [edi], 'e'
    mov     byte ptr [edi+1], 's'
    mov     byte ptr [edi+2], 'i'
    add     edi, 3
    jmp     wr_done
wr_edi:
    mov     byte ptr [edi], 'e'
    mov     byte ptr [edi+1], 'd'
    mov     byte ptr [edi+2], 'i'
    add     edi, 3

wr_done:
    pop eax
    ret
write_reg3 ENDP

END
