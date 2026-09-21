void kmain(void) {
    volatile unsigned short *vga = (unsigned short*)0xB8000;
    vga[0] = ('Z' | (0x07 << 8));
}
