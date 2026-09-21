bits 16
org 0x7c00

mov ax,0x00
mov ds,ax
mov es,ax
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
    mov al,'D' ; TODO: remember to remove these debug prints
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

times 510-($-$$) db 0x00

db 0x55,0xAA
