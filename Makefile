IMG := build/pernil-os.img

.PHONY: build
build:
	@mkdir -p build
	@nasm -f bin boot.asm -o $(IMG)

.PHONY: run
run: run-32bit

.PHONY: run-32bit
run-32bit: build
	@qemu-system-i386 \
		-drive file=$(IMG),format=raw,if=floppy \
		-display cocoa,zoom-to-fit=on

.PHONY: run-64bit
run-64bit: build
	@qemu-system-x86_64 \
		-drive file=$(IMG),format=raw,if=floppy \
		-display cocoa,zoom-to-fit=on

.PHONY: show-bytes
show-bytes: build
	@xxd -g 1 $(IMG)

.PHONY: reverse-bytes
reverse-bytes: build
	@ndisasm -b 16 -o 0x7c00 $(IMG)
