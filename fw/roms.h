#pragma once

#include <stdint.h>

static const uint8_t __attribute__((aligned(4), section(".data" ".rom_chars_8800"))) rom_chars_8800[] = {
    #include "roms/characters-2.901447-10.h"
};

static const uint8_t __attribute__((aligned(4), section(".data" ".rom_basic_b000"))) rom_basic_b000[] = {
    #include "roms/basic-4-b000.901465-23.h"
};

static const uint8_t __attribute__((aligned(4), section(".data" ".rom_basic_c000"))) rom_basic_c000[] = {
    #include "roms/basic-4-c000.901465-20.h"
};

static const uint8_t __attribute__((aligned(4), section(".data" ".rom_basic_d000"))) rom_basic_d000[] = {
    #include "roms/basic-4-d000.901465-21.h"
};

static const uint8_t __attribute__((aligned(4), section(".data" ".rom_edit_e000"))) rom_edit_e000[] = {
    #include "roms/edit-4-40-n-60Hz-ntsc.h"
};

static const uint8_t __attribute__((aligned(4), section(".data" ".rom_kernal_f000"))) rom_kernal_f000[] = {
    #include "roms/kernal-4.901465-22.h"
};