BUILD_DIR  := build

LINKER     := linker.ld

MBR_SRC    := boot/mbr.asm
MBR_BIN    := build/mbr.bin

LOADER_SRC := boot/loader.asm
LOADER_OBJ := build/loader.o

KMAIN_SRC  := kernel/kmain.c
KMAIN_OBJ  := build/kmain.o

KERNEL_ELF := build/kernel.elf
KERNEL_BIN := build/kernel.bin

OS_IMG     := build/minos.img

.PHONY: build
build:
	@mkdir -p $(BUILD_DIR)
	@nasm -f bin $(MBR_SRC) -o $(MBR_BIN)
	@nasm -f elf32 $(LOADER_SRC) -o $(LOADER_OBJ)
	@i686-elf-gcc -march=i386 -m32 -ffreestanding -fno-pie -c $(KMAIN_SRC) -o $(KMAIN_OBJ)
	@i686-elf-ld -T $(LINKER) $(LOADER_OBJ) $(KMAIN_OBJ) -o $(KERNEL_ELF)
	@i686-elf-objcopy -O binary $(KERNEL_ELF) $(KERNEL_BIN)
	@truncate -s 4096 $(KERNEL_BIN)
	@cat $(MBR_BIN) $(KERNEL_BIN) > $(OS_IMG)

.PHONY: run
run: build
	@mkdir -p $(BUILD_DIR)/logs
	@qemu-system-i386 \
		-drive file=$(OS_IMG),format=raw,if=floppy \
		-d int,cpu_reset,guest_errors,in_asm \
		-no-reboot -no-shutdown \
		-D $(BUILD_DIR)/logs/qemu.log \
		-display cocoa,zoom-to-fit=on

.PHONY: show-bytes
show-bytes: build
	@xxd -g 1 $(OS_IMG)

.PHONY: reverse-bytes
reverse-bytes: build
	@ndisasm -b 16 -o 0x7c00 $(OS_IMG)
