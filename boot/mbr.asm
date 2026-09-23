bits 16
org 0x7c00

; Clear segment registers
mov ax,0x00
mov ds,ax
mov es,ax
mov fs,ax
mov gs,ax

mov di,0

welcome:
    mov si,welcome_msg
    add si,di

    ; Call BIOS to print character to screen
    mov ah,0x0E
    mov al,[si]
    mov bh,0
    mov bl,0
    int 0x10

    ; Increments char counter and loop if it's not the end of the string
    add di,1
    cmp di,17
    jne welcome

boot:
    ; Call BIOS to load disk sector containing kernel image into memory address 0x8000
    mov ah,0x02
    mov al,8 ; 8 sectors = 4096 bytes, matches Makefile's truncate size when building kernel image
    mov ch,0
    mov cl,2
    mov dh,0
    mov bx,0x8000
    int 0x13

    jc disk_error

    ; Clean <cs> register and hand-off control to loader.asm at address 0x8000 (defined in linker.ld)
    jmp 0x0000:0x8000

disk_error:
    hlt

; Remember to keep data at the end or jump over them.
; If data comes between instructions CPU will simply not care and start executing bytes as it sees them.
; That can lead to weird behavior and faults.
welcome_msg:
    db "Welcome to MinOS!"

times 510-($-$$) db 0x00

db 0x55,0xAA
