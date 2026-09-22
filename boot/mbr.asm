bits 16
org 0x7c00

mov ax,0x00
mov ds,ax
mov es,ax
mov fs,ax
mov gs,ax

mov di,0

welcome:
    mov si,welcome_msg
    add si,di

    mov ah,0x0E
    mov al,[si]
    mov bh,0
    mov bl,0
    int 0x10

    add di,1
    cmp di,17
    jne welcome

boot:
    mov ah,0x02
    mov al,8      ; 8 sectors = 4096 bytes, matches Makefile's truncate size when building mbr+kernel image together;
    mov ch,0
    mov cl,2
    mov dh,0
    mov bx,0x8000
    int 0x13

    jc disk_error

    jmp 0x0000:0x8000

disk_error:
    hlt

; IPC: remember that data segments must come at the end, or code should jump over them
; correctly. Otherwise cpu doesnt care and will try to load bytes as instructions, leading to errors
welcome_msg:
    db "Welcome to MinOS!"

times 510-($-$$) db 0x00

db 0x55,0xAA
