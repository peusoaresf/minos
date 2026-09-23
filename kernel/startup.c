#define COLS 80
#define ROWS 25

void delay() {
    for (int i = 0; i < 1000000; i++) {}
}

void put_char(volatile unsigned short *vga, int row, int col, char* c) {
    vga[(row * COLS) + col] = ((int)c | (0b00000111 << 8));
}

void startup(void) {
    volatile unsigned short *vga = (unsigned short*)0xB8000;

    for (int row = 0; row < ROWS; row++) {
        for (int col = 0; col < COLS; col++) {
            put_char(vga, row, col, (char*)'A');
            delay();
        }
    }
}
