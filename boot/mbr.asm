; according to https://wiki.osdev.org/MBR_(x86), we need:
; [done] use real mode
; [done] exactly 512 bytes long
; [done] last 2 bytes exactly 0x55 followed by 0xAA
; bootstrap portion at most 446 bytes
; should contain at least one entry in the partition table [optional?]
; [done] MBR is loaded into 0x7c00
; enforce CS:IP with far jump
; [done] set DS, ES, FS, GS segment registers to 0
; set stack registers SS:SP to even unused address

bits 16                       ; sets 16 bit real mode https://www.nasm.us/docs/3.02/nasm08.html#section-8.1
org 0x7c00                    ; instruct nasm to treat addresses as starting at offset 0x7c00

mov ax,0x00                   ; segment registers cannot be loaded directly, thus
mov ds,ax                     ; we load 0 into a general purpose one (ax) and then move it's data
mov es,ax                     ; into the required registers https://wiki.osdev.org/CPU_Registers_x86
mov fs,ax
mov gs,ax

mov di,0                      ; position of the current character read

welcome:
    mov si,bootstrap_msg
    add si,di                 ; loads memory location of char in bootstrap_msg offseted by di

    mov ah,0x0E               ; setup & call interrupt 0x10,E according to specs https://stanislavs.org/helppc/int_10-e.html
    mov al,[si]
    mov bh,0
    mov bl,0
    int 0x10

    add di,1                  ; increments di and loops if di != 20
    cmp di,20
    jne welcome

boot:
    mov ah,0x02
    mov al,8  ; 8 sectors = 4096 bytes, matches Makefile's truncate size when building boot+kernel together;
              ; If these values don't align, it means we never loaded the full kernel binary into memory
              ; and the cpu will simply execute whatever trash bytes comes next, never reaching the kernel code
    mov ch,0
    mov cl,2
    mov dh,0
    mov bx,0x8000
    int 0x13
    jc disk_error

    ; debug print whether disk read succeeds
    mov ah,0x0E
    mov al,'D'
    mov bh,0
    int 0x10

    jmp 0x0000:0x8000

disk_error:
    hlt

; IPC: remember that data segments must come at the end, or code should jump over them
; correctly. Otherwise cpu doesnt care and will try to load bytes as instructions, leading to errors
bootstrap_msg:
    db "Welcome to PernilOS!" ; stores each character sequentially at memory address starting in the label line,
                              ; assuming file starts at address 0 if not told otherwise.
                              ; since BIOS loads bootloader into 0x7c00, references to addresses within this string
                              ; (eg [bootstrap_msg+1]) would target the wrong address thus not work
                              ; should we not specify the base with <org 0x7c00>

times 510-($-$$) db 0x00      ; $ evalutes to current line offset ; $$ evalutes to start of section offset
                              ; so $ - $$ virtually tells us how deep into the file (in bytes) we are
                              ; subtracting that from 510 allows us to guarantee 512 byte long file
                              ; https://www.nasm.us/doc/nasm03.html#section-3.2.5
                              ; https://www.nasm.us/doc/nasm03.html#section-3.5

db 0x55,0xAA                  ; places these exact bytes in this exact order at the end of the file
                              ; https://www.nasm.us/doc/nasm03.html#section-3.2.1
