/**
 * PET Clone - Open hardware implementation of the Commodore PET
 * by Daniel Lehenbauer and contributors.
 * 
 * https://github.com/DLehenbauer/commodore-pet-clone
 *
 * To the extent possible under law, I, Daniel Lehenbauer, have waived all
 * copyright and related or neighboring rights to this project. This work is
 * published from the United States.
 *
 * @copyright CC0 http://creativecommons.org/publicdomain/zero/1.0/
 * @author Daniel Lehenbauer <DLehenbauer@users.noreply.github.com> and contributors
 */

module top(
    // System Bus
    inout bus_rw_b,             // CPU 34          : 0 = CPU writing, 1 = CPU reading
    inout [16:0] bus_addr,      // CPU 9-20, 22-25 : System address bus
    inout [7:0] bus_data,       // CPU 33-26       : System data bus
    
    output [11:10] ram_addr,    // RAM: Intercept A11/A10 to mirror VRAM.  Must remove zero ohm
                                //      resistors at R9 and R10.

    // Pi
    input spi_sclk,             // RPi 23 : GPIO 11
    input spi_cs_n,             // RPi 24 : GPIO 8
    input spi_rx,               // RPi 19 : GPIO 10
    output spi_tx,              // RPi 21 : GPIO 9

    input  pi_pending_b,        // RPi  2 : Pending read/write request from RPi
    output pi_done_b,           // RPi  3 : Request completed and pi_data held while still pending.
    input pi_clk,               // RPi  4 : Clock generated by RPi (no longer used)

    // Timing
    output phi2,                // CPU 37 : 1 MHz cpu clock
    output ram_oe_b,            // RAM 24 : 0 = output enabled, 1 = High impedance
    output ram_we_b,            // RAM 29 : 0 = write enabled,  1 = Not active

    // CPU
    inout  cpu_res_b,           // CPU 40 : 0 = reset, 1 = normal operation
    output cpu_rdy,             // CPU  2 : 0 = halt,  1 = run
    inout  cpu_irq_b,           // CPU  4 : 0 = interrupt requested, 1 = normal operation
    inout  cpu_nmi_b,           // CPU  6 : 0 = interrupt reuested, 1 = normal operation
    input  cpu_sync,

    // Address Decoding
    output cpu_be,              // CPU 36 : 1 = High impedance,  0 = enabled (be)
    output ram_ce_b,            // RAM 22 : 0 = enabled (ce_b),  1 = High impedance
    output pia1_cs2_b,
    output pia2_cs2_b,
    output via_cs2_b,
    output io_oe_b,

    // Audio
    input diag,
    input cb2,
    output audio,

    // Graphics
    input gfx,
    output hsync,
    output vsync,
    output video,

    // DEBUG
    output [7:0] pi_data,
    
    // Reserved by DevBoard
    // (See http://land-boards.com/blwiki/index.php?title=Cyclone_II_EP2C5_Mini_Dev_Board#I.2FO_Pin_Mapping)
    output P3_LED_D2,           // Low to Light LED
    output P7_LED_D4,           // Low to Light LED
    output P9_LED_D5,           // Low to Light LED
    input  P17_50MHz,           // Clock input
    input  P26_1V2,             // VCC 1.2V for EP2C8.  On EP2C5, remove "Zero ohm" resistor tu use pin used as normal.
    input  P27_GND,             // GND for EP2C8.  On EP2C5, remove "Zero ohm" resistor tu use pin used as normal.
    input  P73_POR              // 10uF capacitor to ground + 10K resistor to Vcc (Presumably for power up reset?)
    
    // The following reserved Pins are currently in use:
    //    P80/81 - Removed R9/R10 and used from ram_addr
    //    P144   - Used for cpu_res_b
    //
    // input  P80_GND,             // GND for EP2C8.   On EP2C5, remove "Zero ohm" resistor tu use pin used as normal.
    // input  P81_1V2              // VCC 1.2Vfor EP2C8. On EP2C5, remove "Zero ohm" resistor tu use pin used as normal.    
    // inout P144_KEY              // Push to ground.  Requires internal pullup on FPGA if used.
);
    wire pi_pending = !pi_pending_b;
    wire pi_done;
    assign pi_done_b = !pi_done;

    wire res_b;
    wire irq_b = 1'b1;
    wire nmi_b = 1'b1;

    // res_b, irq_b, and nmi_b are open drain for wire-OR (see also *.qsf)
    assign cpu_res_b = res_b ? 1'bZ : 1'b0;
    assign cpu_irq_b = irq_b ? 1'bZ : 1'b0;
    assign cpu_nmi_b = nmi_b ? 1'bZ : 1'b0;

    assign P3_LED_D2 = pi_pending_b;
    assign P7_LED_D4 = pi_done_b;
    assign P9_LED_D5 = cpu_res_b;
    
    wire clk16;     // 16 MHz clock from PLL
    
    pll pll(
        .inclk0(P17_50MHz),
        .c0(clk16)
    );
    
    // Audio
    assign audio = cb2 && diag;

    // spi_byte debug_byte(
    //    .spi_cs_n(spi_cs_n),
    //    .spi_sclk(spi_sclk),
    //    .spi_rx(spi_rx),
    //    .rx(pi_data)
    //);

    // assign pi_data[0] = spi_sclk;
    // assign pi_data[1] = spi_cs_n;
    // assign pi_data[2] = spi_rx;
    // assign pi_data[3] = spi_tx;

    wire pi_rw_b;
    wire [16:0] pi_addr;
    wire [7:0] pi_wr_data;          // Incoming data when Pi is writing
    wire [7:0] pi_rd_data;          // Outgoing data when Pi is reading
    wire pi_pending_out;
    wire pi_done_in;

    pi_com pi_com(
        .sys_clk(clk16),
        .spi_sclk(spi_sclk),
        .spi_cs_n(spi_cs_n),
        .spi_rx(spi_rx),
        .spi_tx(spi_tx),
        .pi_addr(pi_addr),
        .pi_data_in(pi_rd_data),
        .pi_data_out(pi_wr_data),
        .pi_rw_b(pi_rw_b),
        .pi_pending_in(pi_pending),
        .pi_pending_out(pi_pending_out),
        .pi_done_in(pi_done_in),
        .pi_done_out(pi_done),

        // Expose external state for debugging
        .state(pi_data[2:0]),
        .bit_index(pi_data[5:3]),
        .rx_valid(pi_data[6])
    );
    
    main main(
        .pi_rw_b(pi_rw_b),
        .pi_addr({ 1'b0, pi_addr }),
        .pi_wr_data(pi_wr_data),    // Incoming data when Pi is writing
        .pi_rd_data(pi_rd_data),    // Outgoing data when Pi is reading
        .bus_rw_b(bus_rw_b),
        .bus_addr(bus_addr),
        .bus_data(bus_data),
        .ram_addr(ram_addr),
        .clk16(clk16),
        .phi2(phi2),
        .ram_oe_b(ram_oe_b),
        .ram_we_b(ram_we_b),
        .pi_pending(pi_pending_out),
        .pi_done(pi_done_in),
        .reset_in(!cpu_res_b),
        .res_b_out(res_b),
        .cpu_rdy(cpu_rdy),
        .cpu_sync(cpu_sync),
        .cpu_be(cpu_be),
        .ram_ce_b(ram_ce_b),
        .pia1_cs2_b(pia1_cs2_b),
        .pia2_cs2_b(pia2_cs2_b),
        .via_cs2_b(via_cs2_b),
        .io_oe_b(io_oe_b),
        .gfx(gfx),
        .hsync(hsync),
        .vsync(vsync),
        .video(video)
    );
endmodule