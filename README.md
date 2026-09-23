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

### The OS Image

The following is a summary table detailing the OS image, all of its sections and what each section contains / is responsible for. This is basically how the OS image file is subdivided, ie how all of the bytes inside `minos.img` are layed out.

I know it's a lot to take in at once and too much for a first glimpse inside the operating system's internals, but keep in mind this is mostly a good reference table of the overall structure and responsibilities.

Feel free to skim through, register some names here and there in the background of your mind, but worry not, as we'll dive deeper into each component:

| Offset | Section | Size | Contents |
|--------|---------|------|----------|
| 0x0000 | MBR                 | 512 B  | `boot/mbr.asm` <br> bootloader stage 1, real mode, BIOS entrypoint, disk read, handoff to stage 2 |
| 0x0200 | Kernel Image        | 4096 B | `boot/loader.asm` + `kernel/startup.c` |
|        | &nbsp;↳ Loader      |        | `boot/loader.asm` <br> bootloader stage 2, A20 line, GDT, protected mode switch, handoff to startup.c |
|        | &nbsp;↳ Startup     |        | `kernel/startup.c` <br> Kernel entrypoint |

_**Kernel Image** is the combined linked binary containing both the loader (final boot responsibility) and the actual kernel (startup.c and beyond)._

### Loading the Kernel Image

Before we can even think about venturing on any OS-related features, we have **to load the kernel** somehow. This 'somehow', at least for legacy IBM-Compatible BIOS pcs, **means creating a piece of code called 'bootloader' that is shaped in a very specific way** (in order to be picked-up by the bios and executed), **performs some very specific tasks** (required by the IBM-Compatible BIOS' expectations) **and ultimately loads our kernel image into memory** and starts execution.

This is a major summary of the many things I've read over the recent past, written by much more knowledgeable people than me, and I'll always link where I getting stuff from (just in case my summarizations might be too simplistic or maybe outright wrong in a very deep technically spoken way, let's say, so sorry in advance! Oh, and I'll for sure mention a lot the people/articles over wiki.osdev.org).

Now is probably a good time to tell you that the aforementioned is gonna be achieved by programming in `assembly` language. Worry not, we'll eventually move up to C for actual kernel code, but we gotta get our hands on the hardware first. You'll also notice that bootloading is achieved in 2 stages. This is due to the fact that stage 1 is incredibly limited (due to real mode BIOS hard constraints).

---

#### MBR (Stage 1)

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

_Code in this section can be found in the `boot/mbr.asm` file._

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

In order for the BIOS to properly recognize this image section as our booting procedure, we must end it with the bytes 0x55AA. Yes. Hardcoded. Those values. Not much to think about.

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

Before we get closer to ever running any C code, why not say a quick hi to users, just so we know our MBR code actually works and is capable of doing something a bit more useful.

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

- **Loading kernel image from disk and delegating execution to it**

Now it comes the time we've all been waiting for: loading the kernel image from disk and delegating execution to it. Very very soon we gonna have some C code ready to run, worry not.

We'll leverage, once again, BIOS interrupts to [interact with the disk](https://stanislavs.org/helppc/int_13-2.html) and load the sectors of our image that contain the stage 2 bootloader + startup kernel code (ie the **kernel image**).

We achieve that by:
1. Making a read call to the boot disk (current disk) of size 8 sectors (equals 4096 bytes, the full size of the kernel image);
2. Instructing the disk to read from sector 2 onwards (sector 1 holds our MBR, which is already running, we can safely skip it);
3. Asking the disk to load the data into address 0x8000 (our `linker.ld` ensures the kernel image is aware of this);
4. Performing a far jump to address 0x8000, essentially handing control to the stage 2 bootloader.

So, right after the `welcome` assembly section, but before the `boostrap_msg` data definition, we place the boot procedure:

```assembly
; Since we are 'inside' MBR code, the boot disk number
; (which is the one we are interested in) is already loaded into <dl>.
; Thus there's no need to explicitly set 'mov dl,X' when setting up the interrupt.

boot:
    mov ah,0x02
    mov al,8          ; 8 sectors = 4096 bytes. 
                      ; Matches Makefile's truncate size applied to the kernel image binary.
                      ; Thus we can safely load a chunk of that size without worrying about trash.
                      ; ..If these values don't align, we risk the cpu executing whatever 
                      ; trash bytes comes next, never reaching the kernel image code
    mov ch,0
    mov cl,2          ; 1-indexed sector we want to load from. 
                      ; 1st sector holds MBR which is already in memory.
                      ; We ignore it and start loading kernel image which resides from sector 2.
    mov dh,0
    mov bx,0x8000     ; The disk read interrupt expects a memory address to load data into.
                      ; We set it by defining a 'segment:offset' couple held in the 'es:bx' registers.
                      ; We can assume <es> is zero, since it's a part of the initial cleanup of the MBR.
                      ; With that said, the target address becomes exactly equal to <bx>.
                      ; Thus we essentially instruct the BIOS to load the kernel image into address 0x8000.
    int 0x13

    jc disk_error     ; If the CPU carry flag is set, disk read failed so just stop.

    jmp 0x0000:0x8000 ; Far jumps to the memory address we just loaded.
                      ; This essentially hands control to the stage 2 bootloader loaded there.
                      ; The far jump address syntax works similarly to the disk read explained above.

disk_error:
    hlt
```

---

#### Loader (Stage 2)

Okay, maybe I set us up for too much excitement by stating 'now comes the moment we've all been waiting for' and gave the idea we were about to jump into some kernel code written in C.... almost! We still have some final CPU preparations to get out of the way, but I promise it should be quick and mostly convention based.

Considering stage 1 already made sure our drive is picked up by the BIOS and handed control of the hardware to us, now it's all a matter of:

1. Blocking hardware interrupts to allow our stage 2 to safely  run from start to end uninterrupted;
2. Making sure we have access to all memory (by enabling the A20 line.. whatever that is);
3. Seting up memory access and protection behavior and switching CPU to protected mode;
4. Seting up a clean stack and handing off execution control to the kernel (our OS' C entrypoint!).

As mentioned, many of these are based on conventions or ripped straight out of specs/docs to keep the bootloader pragmatic and minimal. I'll keep linking whatever reference I can in order to keep raw hardware details close enough, but outside of the scope of this readme (I'm not a hardware or assembly expert if you haven't notice .. haha).

_Code in this section can be found in the `boot/loader.asm` file._

- **Blocking interrupts**

Remember that when the MBR handed control off to us, we were still running in 16 bit real mode. That still applies (thus we have to explicitly start the file with the bits 16 snippet)

With that said, in order to disable interrupts we simple write the following:

```assembly
bits 16
cli
```

That way, we make sure no hardware interrupts (such as keyboard) will ever reach the cpu and risk breaking the remaining of our bootstrapping. 

- **Accessing all memory (A20 line)**

In order to be able to access the full memory available we gotta play with the A20 line knob. And who does want to limit themselves in memory?!

This is a requirement due to historical reasons. I can't possibly know all details or even think it's very valuable to do so right now, so we can find all details [here](https://wiki.osdev.org/A20_Line). 

Let's not dangle on the topic too much, we can call a simple BIOS interrupt to solve this:

```assembly
enable_a20:
    mov ax, 0x2401
    int 0x15
```

- **Setting up memory access and protection rules**

We can't simply keep running in 16bit real mode forever right? It's highly limited and unconstrained (ie unsafe), so we better prepare and switch the processor into it's full feature set: 32bit protected mode.

For that we are gonna have to setup something called a Global Descriptor Table (GDT) first. What's a GDT you might ask?... well... I just recently discovered about it myself, so the best way I can describe it in my own words is that the GDT is a set of configurations that instructs the CPU on how to _access_ and _protect_ memory. This configuration is achieved by placing blocks of 8 bytes in sequence describing segments of memory and how they should behave (and isolated bits within the bytes blocks may control specific behavior).

When creating these memory segments, there are three main configurations the GDT provides that are of interest to us: 1. setting the size and granularity of the segment (from which address until which address our space is comprised, and how wide it actually is); 2. setting protection of said segment, marking it as readable, writable and/or executable; and 3. turning on 32bit segment operations.

I'm 110% sure I've skipped over so much that it's insane, but still, it's a very complicated topic on its own and I had to stay pragmatic when setting it up, otherwise I'd never get a kernel up and running. If you want a deeper dive into it, you can check [all of the bits comprising GDT sections](https://wiki.osdev.org/Global_Descriptor_Table) or [how to set a basic one up](https://wiki.osdev.org/GDT_Tutorial#Flat_/_Long_Mode_Setup).

For us, the second link will be a bit more important now, since it provides sensible defaults for a minimal OS, that is, setting up only 2 memory segments, one for code, another for data, kernel level access within each, no crazy isolation or paging in place. So, following the GDP contents displayed there, we can describe a GDT like so at the end of the file:

```assembly
gdt_start:
    dq 0x0000000000000000 ; 1st section has to be a null descriptor.

gdt_code:
    dw 0xFFFF             ; Memory segment spans the whole 4GB space 
    dw 0x0000             ; (0000 to FFFF times 4KB granularity set below).
    db 0x00
    db 0x9A               ; Sets code segment as executable + readable (never writable).
    db 0xCF               ; Sets 4KB granularity and 32 bit segment operations.
    db 0x00 ;

gdt_data:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92               ; Only differing setting for data,
    db 0xCF               ; it should be writable and readable (never executable).
    db 0x00

gdt_end:

gdtr:
    dw gdt_end - gdt_start - 1
    dd gdt_start
```

You'll notice we are leveraging assembly's section labels in order to have a reference to the GDT's addresses at various moments (start, code, data and end), in order to compute the required addresses we are actually gonna load inside the `gdt` register right before enabling protected mode.

- **Switching to protected mode**

Now that we have the GDT described in memory, we can finally switch the CPU to [protected mode](https://wiki.osdev.org/Protected_Mode)! (remember, the GDP is **required** in order to do so. Protected mode _conveys protection_, GDT _describes such protection_). We'll first start by loading the table starting address in the appropriate register, set the CPU security flag to enabled and finally set up the data segment registers.

```assembly
protected_mode_switch:
    lgdt [gdtr]    ; load <gdt> register with start address of the Global Descriptor Table.

    mov eax,cr0
    or al,1
    mov cr0,eax    ; We can operate on the Control Register directly, 
                   ; so through the eax register, we perform an OR operation on 
                   ; the very first bit stored on it in order to flip it from 0 -> 1,
                   ; thus enabling it (the 1st bit of the <cr> register is the CPU Security flag).



    ; From now on the CPU operates in protected mode and under 32 bit segment operations



    mov ax,0x10    ; But wait, we still need to load the index (ie offset)
    mov ds,ax      ; of the data segment of the gdt into the data registers.
    mov es,ax      ; Remember our GDT is composed of 8 byte blocks?
    mov fs,ax      ; 1st one is NULL, 2nd is code and only 3rd is data.
    mov gs,ax      ; 0x10 in decimal is 16 so... thus we offset (skip) both null and code to reach data.


    ; Far jump sets <cs> register to the offset of the code segment within the GDT (skips null).
    ; We have to do it here to reliable instruct the cs to align with our GDT configurations,
    ; otherwise address operations will resolve to the wrong values and fault!
    jmp 0x08:_main
```

- **Setting up the stack and finally handing off to Kernel!**

Now we really are where we've wanted to be all along, right there, ready to run a bare bones OS written in C!

All we have to do is setup the stack, cause that's where our C code is gonna be pushing and popping data from when performing operations and call the kernel startup function.

For that we first instruct nasm to treat the code as 32 bit from here on out (remember we just switched the CPU to protected mode 32 bit), force the <sp> register to a safe unused address far far away from where our loaded kernel image is sitting and last but not least, hand-off control to the kernel startup function:


```assembly
bits 32
_main:
    mov esp,0x90000 ; Sets up the stack with a safe unused address
                    ; (no way we can rely on leftover trash from real mode).
                    ; Stack grows 'downwards' ('push'es decrements esp) before writes,
                    ; so it has to sit comfortably far above the initial kernel image
                    ; loaded at address (0x8000).

    call startup
```

That's it! Now our `kernel/startup.c` file will take control over the system and we can keep on evolving our OS from there! Yeyyy

- **One last thing to address before fully moving on to the kernel: _stitching it all together_**

I haven't mentioned it before just to avoid complexity up front, but we gotta somehow link things together. What that means is, the MBR code will redirect the CPU to continue execution from a certain address and the loader code must know where to pick up where the MBR left it off. For that, at the top of the `loader.asm` file we have define an entrypoint with:

```assembly
global _loader
```

That name is reference in the `linker.ld` file alongside the base address the loader should assume be using while operating (so operations resolve correctly from that base):

```
ENTRY(_loader)

SECTIONS
{
    . = 0x8000;
.
.
.
```

This is the connective tissue between `boot/mbr.asm` and `boot/loader.asm`, making the call to `jmp 0x0000:0x8000` from the former land on the latter.

When it comes to the loader calling the kernel startup function, that's achieved by defining the call to startup as something that's gonna be externally linked to the assembly, once again, at the top of the file you'll notice:

```
extern startup
```

Which means to say that when compiling `loader.asm` into an object file, even though `startup` is not define anywhere, the compiler should not freak out. It's going to be provided in a later step before generating the final binary. And that's exactly what we do by compiling both sources -> linking them together -> generating a binary containing both in the makefile:

```bash
# compiles the loader to an object and the 'extern' keyword makes sure the compiler won't break due to the absence of 'startup'
nasm -f elf32 boot/loader.asm -o build/loader.o

# compiles the kernel startup file
i686-elf-gcc -march=i386 -m32 -ffreestanding -fno-pie -c kernel/startup.c -o build/startup.o

# links both together, gluing the startup call present in one source file to its definition present in the other
i686-elf-ld -T linker.ld build/loader.o build/startup.o -o build/kernel_image.elf
```

That's it, now we can really go on to more fun and """"higher"""" level stuff... let's see if we keep that good energy when building device drivers lmaooo.

### The Kernel

TODO: _Work-in-progress._

---
 
_TODO: Important links for docs, remove after_

https://en.wikipedia.org/wiki/VGA_text_mode

https://cdrdv2.intel.com/v1/dl/getContent/671200 (intel manual)
