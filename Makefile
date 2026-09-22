BUILD_DIR      := build

LINKER         := linker.ld

MBR_SRC        := boot/mbr.asm
MBR_BIN        := build/mbr.bin

LOADER_SRC     := boot/loader.asm
LOADER_OBJ     := build/loader.o

STARTUP_SRC    := kernel/startup.c
STARTUP_OBJ    := build/startup.o

KERNEL_IMG_ELF := build/kernel_image.elf
KERNEL_IMG_BIN := build/kernel_image.bin

OS_IMG         := build/minos.img

.PHONY: build
build:
	@mkdir -p $(BUILD_DIR)
	@nasm -f bin $(MBR_SRC) -o $(MBR_BIN)
	@nasm -f elf32 $(LOADER_SRC) -o $(LOADER_OBJ)
	@i686-elf-gcc -march=i386 -m32 -ffreestanding -fno-pie -c $(STARTUP_SRC) -o $(STARTUP_OBJ)
	@i686-elf-ld -T $(LINKER) $(LOADER_OBJ) $(STARTUP_OBJ) -o $(KERNEL_IMG_ELF)
	@i686-elf-objcopy -O binary $(KERNEL_IMG_ELF) $(KERNEL_IMG_BIN)
	@truncate -s 4096 $(KERNEL_IMG_BIN)
	@cat $(MBR_BIN) $(KERNEL_IMG_BIN) > $(OS_IMG)

.PHONY: run
run: build
	@mkdir -p $(BUILD_DIR)/logs
	@qemu-system-i386 \
		-drive file=$(OS_IMG),format=raw,if=floppy \
		-d int,cpu_reset,guest_errors,in_asm \
		-no-reboot -no-shutdown \
		-D $(BUILD_DIR)/logs/qemu.log \
		-display cocoa,zoom-to-fit=on

.PHONY: os-img-dump
os-img-dump: build
	@xxd -g 1 $(OS_IMG)

.PHONY: mbr-dump
mbr-dump: build
	@ndisasm -b 16 -o 0x7c00 $(MBR_BIN)

.PHONY: kernel-img-dump
kernel-img-dump: build
	objdump -d $(KERNEL_IMG_ELF)

.PHONY: kernel-img-symbols
kernel-img-symbols: build
	nm $(KERNEL_IMG_ELF)
