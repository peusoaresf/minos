bits 16
global enable_a20

cli

enable_a20:
    mov ax, 0x2401
    int 0x15

protected_mode_switch:
    lgdt [gdtr]    ; load GDT register with start address of Global Descriptor Table
    mov eax,cr0
    or al,1       ; set PE (Protection Enable) bit in CR0 (Control Register 0)
    mov cr0,eax

    jmp 08h:_main ; jump to code segment in gdt

bits 32
_main:
    mov ax,0x10 ; load data segment into registers
    mov ds,ax
    mov es,ax
    mov fs,ax
    mov gs,ax
    mov ss,ax
    mov esp,0x90000

    mov word [0xB8002],0x0742

    extern kmain
    call kmain

hang:
    hlt
    jmp hang

gdt_start:
    dq 0x0000000000000000

gdt_code:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x9A
    db 0xCF
    db 0x00

gdt_data:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92
    db 0xCF
    db 0x00

gdt_end:

gdtr:
    dw gdt_end - gdt_start - 1
    dd gdt_start
