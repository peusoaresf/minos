void startup(void) {
    for (int i = 0; i < 1000000000; i++) {
        // delay before displaying the Z character
    }
    volatile unsigned short *vga = (unsigned short*)0xB8000;
    vga[0] = ('Z' | (0x07 << 8));
}
