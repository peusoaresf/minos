# MinOS

A work-in-progress project towards a minimal operating system for i386 machines.

## Dependencies 

- [NASM](https://www.nasm.us/)
- [QEMU](https://www.qemu.org/download/)
- [Cross-Compiler](https://wiki.osdev.org/GCC_Cross-Compiler#Preparing_for_the_build)
    - _ps.: on MacOS we can simply `brew install i686-elf-gcc` to get a compatible cross-compiler ready for our target arch (i386)_

## Quick Start

Simply run:

```
make run
```

And the script will make sure to build the code and run the OS image on a i386 QEMU emulator.

## Creating MinOS

I'll try my best to document the journey of building the main components of the OS, from bootloading to essential kernel drivers/modules. I'll walkthrough the main code snippets, quirks to be aware of and important lessons-learned.

### Loading the Kernel

Before we can even think about venturing on any OS-related features, we have **to load the kernel** somehow. This 'somehow', at least for legacy IBM-Compatible BIOS pcs, **means creating a piece of code called 'bootloader' that is shaped in a very specific way** (in order to be picked-up by the bios and executed), **performs some very specific tasks** (required by the IBM-Compatible BIOS' expectations) **and ultimately loads our kernel code into memory** and starts execution.

This is a major summary of the many things I've read over the recent past, written by much more knowledgeable people than me, and I'll always link where I getting stuff from (just in case my summarizations might be too simplistic or maybe outright wrong in a very deep technically spoken way, let's say, so sorry in advance! Oh, and I'll for sure mention a lot the people/articles over wiki.osdev.org).

Now is probably a good time to tell you that the aforementioned is gonna be achieved by programming in `assembly` language. Worry not, we'll eventually move up to C for actual kernel code, but we gotta get our hands on the hardware first.

---

#### MBR

In order to achieve what I just wrote down, we first have to setup an MBR. The MBR, in the most simplistic way possible I can imagine, is the very first section (or, well.. literally 'part') of your OS image (or.. the bytes we are gonna burn to a disk and try to execute in order to spin-up the kernel) which performs some preparatory work (interfacing with the bios where needed) and loads the kernel image off the disk and into memory.

According to this very detailed [article on MBRs](https://wiki.osdev.org/MBR_(x86)) a minimal MBR would require:
1. Run in real mode;
2. Be exactly 512 bytes long;
3. The last 2 bytes be exactly 0x55 followed by 0xAA;
4. Loaded into 0x7c00;
5. Enforce CS:IP with far jump;
6. DS, ES, FS, GS segment registers should be set to 0;
7. Stack registers SS:SP should be set to even unused address.

I'll already spoil the fun and note that, throughout my experimentations with QEMU, 5 and 7 were not required..... although I know this is probably setting me up for a weird bug in a near future should I ever run this code in other platforms/hardware. 

Moving on. Let's see each one of those in detail (though not necessarily in order).

- **Running in real mode**

At least [when using NASM](https://www.nasm.us/docs/3.02/nasm08.html#section-8.1), running in real mode simply means starting out the file as:

```assembly
bits 16
```

And what is real mode?... well, I'll let [this page](https://wiki.osdev.org/Real_Mode) explain it better than I could, but to simplify, it's a simplistic mode present in all x86 processors that operates in 16-bit and is heavily limited (and maybe even dangerous, why would you even run user processes here.. careful).

- **Loading into 0x7c00**

While setting up some general stuff, we gotta instruct NASM to treat address and addresses resolutions as though they are starting at offset 0x7c00, cause that's exactly where the BIOS will load the program when it's found. We achieve that by writing at the top of the file right below the real mode:

```assembly
org 0x7c00
```

- **Zeroing segment registers**

Just a matter of cleaning up any potential trash and leaving registers at a consistent starting state, we gotta clean up the segment registers DS, ES, FS and GS. To do that, we can't simply load them directly with a mov command (eg `mov ds,0x00`), we have to use an intermediary [general purpose](https://wiki.osdev.org/CPU_Registers_x86#General_Purpose_Registers) register for that and then move the data into the required registers:

```assembly
mov ax,0x00
mov ds,ax
mov es,ax
mov fs,ax
mov gs,ax
```

- **Ending with magic signature 0x55AA**

In order for the BIOS to properly recognize the image as our booting procedure, we must end it with the bytes 0x55AA. Yes. Hardcoded. Those values. Not much to think about.

With NASM we can declare data values with the [db](https://www.nasm.us/doc/nasm03.html#section-3.2.1) command (among a few others). So, at the very end of the file just place:

```assembly
db 0x55,0xAA
```

- **Being exactly 512 bytes long**

And, to finish off the 'BIOS detecting our boot code', our mbr section has to be exactly 512 bytes long (from the first instruction all the way up to the magic signature, included).

For that, we are gonna pad the assembly with a noop instruction `db 0x00` (we are basically filling 0 bytes in there) using the `times` nasm command that repeats the line X times. We'll couple that with some simple address offset calculations and place the `times` operation right before the magic signature, making sure that regardless of whether our mbr code grows or shrinks, we are always gonna pad from where we left off until the byte 510 (remember we have 2 bytes at the end already):

```assembly
times 510-($-$$) db 0x00    ; $ evalutes to current line address offset.
                            ; $$ evalutes to start of section address offset.
                            ; $ - $$ virtually tells us how deep into the file (in bytes) we are.
                            ; Subtracting that from 510 allows us to guarantee 512 byte long file.
                            ; https://www.nasm.us/doc/nasm03.html#section-3.2.5
                            ; https://www.nasm.us/doc/nasm03.html#section-3.5
```

That gets us done with the MBR setup, and from here on out we are already pretty much in control of the machine. Should you really wish to, you could write minimal procedures that leverage BIOS interrupt calls to do stuff such as: interacting with disk, keyboard or the video output. For a complete kernel, this gets very limitting (at least for today's standards) but we'll leverage some of that to tread towards more fun stuff.

- **Saying 'Welcome'**

Before we get closer to ever loading our C Kernel code, why not say a quick hi to users, just so we know our MBR code actually works and is capable of doing something a bit more useful.

For that, we are going to: 1. define a constant to hold our welcome string; and 2. print each character individually (by address + character index). We'll leverage BIOS interrupts to print to the screen and simple register manipulation in order to loop all characters:


```assembly
mov di,0                    ; Position of the current character read.

welcome:
    mov si,welcome_msg
    add si,di               ; Loads memory location of char in welcome_msg offseted by di.

    mov ah,0x0E             ; Setup & call BIOS interrupt 0x10,E according to specs https://stanislavs.org/helppc/int_10-e.html
    mov al,[si]
    mov bh,0
    mov bl,0
    int 0x10

    add di,1                ; Increments di and loops if di != 17 (the length of our string).
    cmp di,17
    jne welcome

welcome_msg:
    db "Welcome to MinOS!"  ; Stores each character sequentially at memory address starting in the label line 
                            ; (assumes file starts at address 0 if not told otherwise).
                            ; Since BIOS loads mbr into 0x7c00, references to addresses within this string
                            ; (eg [bootstrap_msg+1]) would target the wrong address thus not work
                            ; should we not specify the base with <org 0x7c00>.
```

That will get the string `Welcome to MinOS!` printed to the screen, which gets us to the very last step of our MBR:

- **Loading kernel from disk and delegating execution to it**

Now it comes the time we've all been waiting for: loading the kernel from disk and delegating execution to it. Very very soon we gonna have some C code ready to run, worry not.

We'll leverage, once again, BIOS interrupts to [interact with the disk](https://stanislavs.org/helppc/int_13-2.html) and load the sectors of our image that contain the kernel code.

We achieve that by:
1. Making a read call to the boot disk (current disk) of size 8 sectors (equals 4096 bytes, the full size of the kernel portion of our OS image);
2. Instructing the disk to read from sector 2 onwards (sector 1 holds our MBR, which is already running, we can safely skip it);
3. Asking the disk to load the data into address 0x8000 (our `linker.ld` ensures the kernel is aware of this);
4. Performing a far jump to address 0x8000, essentially handing control to the kernel.

So, right after the `welcome` assembly section, but before the `boostrap_msg` data definition, we place the boot procedure:

```assembly
; Since we are 'inside' MBR code, the boot disk number
; (which is the one we are interested in) is already loaded into <dl>.
; Thus there's no need to explicitly set 'mov dl,X' when setting up the interrupt.

boot:
    mov ah,0x02
    mov al,8          ; 8 sectors = 4096 bytes. 
                      ; Matches Makefile's truncate size applied to the kernel binary.
                      ; Thus we can safely load a chunk of that size without worrying about trash.
                      ; ..If these values don't align, we risk the cpu executing whatever 
                      ; trash bytes comes next, never reaching the kernel code
    mov ch,0
    mov cl,2          ; 1-indexed sector we want to load from. 
                      ; 1st sector holds MBR which is already in memory.
                      ; We ignore it and start loading kernel which resides from sector 2.
    mov dh,0
    mov bx,0x8000     ; The disk read interrupt expects a memory address to load data into.
                      ; We set it by defining a 'segment:offset' couple held in the 'es:bx' registers.
                      ; We can assume <es> is zero, since it's a part of the initial cleanup of the MBR.
                      ; With that said, the target address becomes exactly equal to <bx>.
                      ; Thus we essentially instruct the BIOS to load the kernel into address 0x8000.
    int 0x13

    jc disk_error     ; If the CPU carry flag is set, disk read failed so just stop.

    jmp 0x0000:0x8000 ; Far jumps to the memory address we just loaded.
                      ; This essentially hands control to the kernel code loaded there.
                      ; The far jump address syntax works similarly to the disk read explained above.

disk_error:
    hlt
```

---

#### Loader

_Work-in-progress._

### Kernel

_Work-in-progress._

---
 
_Important links for docs:_

https://en.wikipedia.org/wiki/VGA_text_mode

https://wiki.osdev.org/A20_Line

https://wiki.osdev.org/Protected_Mode

https://wiki.osdev.org/GDT_Tutorial
