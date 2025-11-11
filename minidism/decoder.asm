option casemap:none
.386
.model flat, c
.stack 4096

.code

; void __cdecl decoder_init(void);
decoder_init PROC C
    ; (no-op for now)
    ret
decoder_init ENDP

; int __cdecl decode_one(const uint8_t* buf,int len,int off,uint32_t base,char* out,int outcap,int hexOn)
decode_one PROC C pBuf:PTR BYTE, len:DWORD, off:DWORD, base:DWORD, pOut:PTR BYTE, outcap:DWORD, hexOn:DWORD
    push    ebx
    push    esi
    push    edi

    ; esi = buf + off
    mov     esi, pBuf
    add     esi, off

    ; need at least one byte
    mov     eax, len
    cmp     eax, 1
    jl      unknown

    ; AL = opcode
    movzx   eax, byte ptr [esi]
    cmp     al, 090h           ; NOP
    je      is_nop
    cmp     al, 0C3h           ; RET
    je      is_ret
    jmp     unknown

is_nop:
    ; write "nop" to out
    mov     edi, pOut
    mov     byte ptr [edi+0], 'n'
    mov     byte ptr [edi+1], 'o'
    mov     byte ptr [edi+2], 'p'
    mov     byte ptr [edi+3], 0
    mov     eax, 1             ; consumed 1 byte
    jmp     done

is_ret:
    ; write "ret" to out
    mov     edi, pOut
    mov     byte ptr [edi+0], 'r'
    mov     byte ptr [edi+1], 'e'
    mov     byte ptr [edi+2], 't'
    mov     byte ptr [edi+3], 0
    mov     eax, 1
    jmp     done

unknown:
    xor     eax, eax           ; return 0 for unknown/incomplete

done:
    pop     edi
    pop     esi
    pop     ebx
    ret
decode_one ENDP


END
