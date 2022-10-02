#include "pch.h"
#include "global.h"
#include "roms.h"
#include "usb/usb.h"
#include "dvi/dvi.h"

#define PENDING_B_PIN 6
#define DONE_B_PIN 7

#define SPI_INSTANCE spi0
#define SPI_SCK_PIN 2
#define SPI_TX_PIN 3
#define SPI_RX_PIN 4
#define SPI_CSN_PIN 5

volatile uint32_t success = 0;

void pi_write(uint16_t addr, uint8_t data) {
    uint8_t addr_hi = addr >> 8;
    uint8_t addr_lo = addr & 0xff;

    uint8_t bytes [] = { 0x84, addr_hi, addr_lo, data };

    gpio_put(PENDING_B_PIN, 0);
    while(!gpio_get(DONE_B_PIN));

    spi_write_blocking(SPI_INSTANCE, bytes, sizeof(bytes));
    
    // Wait for the Pi to respond
    while(gpio_get(DONE_B_PIN));
    gpio_put(PENDING_B_PIN, 1);

    success++;
}

void set_cpu(bool reset, bool run) {
    pi_write(0xE80F,
        (reset ? 0 : (1 << 0))          // res_b
        | (run ? (1 << 1) : 0));        // rdy
    
    sleep_ms(1);
}

void copy_rom(const uint8_t const* pRom, uint16_t start, uint16_t byteLength) {
    const uint8_t* pSrc = pRom;
    int end = start + byteLength;
    for (int addr = start; addr < end; addr++) {
        pi_write(addr, *pSrc++);
    }
}

void init() {
    stdio_init_all();

    gpio_init(PENDING_B_PIN);
    gpio_set_dir(PENDING_B_PIN, GPIO_OUT);
    gpio_put(PENDING_B_PIN, 1);
    sleep_ms(1);
    
    gpio_init(DONE_B_PIN);
    gpio_set_dir(DONE_B_PIN, GPIO_IN);

    spi_init(SPI_INSTANCE, /* 1 MHz */ 1000 * 1000);
    gpio_set_function(SPI_SCK_PIN, GPIO_FUNC_SPI);
    gpio_set_function(SPI_TX_PIN, GPIO_FUNC_SPI);
    gpio_set_function(SPI_RX_PIN, GPIO_FUNC_SPI);
    gpio_set_function(SPI_CSN_PIN, GPIO_FUNC_SPI);

    set_cpu(/* reset: */ true, /* run: */ false);
    set_cpu(/* reset: */ false, /* run: */ true);

    copy_rom(rom_chars_8800,  0x8800, sizeof(rom_chars_8800));
    copy_rom(rom_basic_b000,  0xb000, sizeof(rom_basic_b000));
    copy_rom(rom_basic_c000,  0xc000, sizeof(rom_basic_c000));
    copy_rom(rom_basic_d000,  0xd000, sizeof(rom_basic_d000));
    copy_rom(rom_edit_e000,   0xe000, sizeof(rom_edit_e000));
    copy_rom(rom_kernal_f000, 0xf000, sizeof(rom_kernal_f000));

    // Reset and resume CPU
    set_cpu(/* reset: */ true, /* run: */ false);
    set_cpu(/* reset: */ false, /* run: */ true);
}

int __not_in_flash("main") main() {
    init();
    usb_init();
    video_init(rom_chars_8800);

    while (true) {
        // Dispatch TinyUSB events
        tuh_task();

        for (uint8_t row = 0; row < sizeof(key_matrix); row++) {
            pi_write(0xe800 + row, key_matrix[row]);
        }
    }

    __builtin_unreachable();
}