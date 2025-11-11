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

    ; need >= 1 byte
    mov     eax, len
    cmp     eax, 1
    jl      unknown

    ; opcode
    movzx   eax, byte ptr [esi]
    mov     bl, al

    ; ---- simple one-byte ----
    cmp     bl, 090h
    je      do_nop
    cmp     bl, 0C3h
    je      do_ret
    cmp     bl, 0CCh
    je      do_int3

    ; ---- MOV r32, imm32 (B8..BF) ----
    cmp     bl, 0B8h
    jb      unknown
    cmp     bl, 0BFh
    ja      unknown

    ; need 5 bytes total
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
    cmp     eax, 0
    je      reg_eax
    cmp     eax, 1
    je      reg_ecx
    cmp     eax, 2
    je      reg_edx
    cmp     eax, 3
    je      reg_ebx
    cmp     eax, 4
    je      reg_esp
    cmp     eax, 5
    je      reg_ebp
    cmp     eax, 6
    je      reg_esi
    ; else 7 → edi
reg_edi:
    ; was mov     dword ptr [edi], 'die'  ; "edi" (little-endian) produced "eid"
    mov     dword ptr [edi], 'ide'      ; little-endian -> "edi"
    add     edi, 3
    jmp     reg_done
reg_eax:  mov dword ptr [edi], 'xae' ; "eax"
          add edi, 3
          jmp reg_done
reg_ecx:  mov dword ptr [edi], 'xce' ; "ecx"
          add edi, 3
          jmp reg_done
reg_edx:  mov dword ptr [edi], 'xde' ; "edx"
          add edi, 3
          jmp reg_done
reg_ebx:  mov dword ptr [edi], 'xbe' ; "ebx"
          add edi, 3
          jmp reg_done
reg_esp:  mov dword ptr [edi], 'pse' ; "esp"
          add edi, 3
          jmp reg_done
reg_ebp:  mov dword ptr [edi], 'pbe' ; "ebp"
          add edi, 3
          jmp reg_done
reg_esi:  mov dword ptr [edi], 'ise' ; "esi"
          add edi, 3
reg_done:

    ; write ", 0x"
    mov     dword ptr [edi], ' ,'
    mov     byte  ptr [edi], ','     ; fix order for ", "
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

END
