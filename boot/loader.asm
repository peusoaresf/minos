bits 16
global _loader
extern startup

_loader:
    cli ; Disable hardware interrupts

enable_a20:
    ; Call BIOS to enable full memory access
    mov ax, 0x2401
    int 0x15

protected_mode_switch:
    lgdt [gdtr] ; Load GDT

    ; Enable CPU security flag
    mov eax,cr0
    or al,1
    mov cr0,eax

    ; Load offset of GDT data segment into registers
    mov ax,0x10
    mov ds,ax
    mov es,ax
    mov fs,ax
    mov gs,ax
    mov ss,ax

    jmp 0x08:_main ; Set <cs> register to GDT code segment and jump to _main

bits 32
_main:
    mov esp,0x90000 ; Set up a clean stack

    call startup ; Hand-off to kernel

gdt_start:
    dq 0x0000000000000000

gdt_code:
    dw 0xFFFF
    dw 0x0000 ; Address space 4GB (0000 -> FFFF * 4KB)
    db 0x00
    db 0x9A   ; Sets segment as executable + readable (never writable)
    db 0xCF   ; sets 4KB granularity and 32 bit segment operations
    db 0x00

gdt_data:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92   ; Sets segment as writable (never executable)
    db 0xCF
    db 0x00

gdt_end:

gdtr:
    dw gdt_end - gdt_start - 1
    dd gdt_start
