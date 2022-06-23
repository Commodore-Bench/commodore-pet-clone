/**
 * PET Clone - Open hardware implementation of the Commodore PET
 * by Daniel Lehenbauer (and contributors).
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

module sync (
    input clk,
    input select,
    input pending,          // read/write is pending
    output strobe,
    output done             // read/write has completed
);
    parameter [1:0] IDLE    = 2'b00,
                    PENDING = 2'b01,
                    DONE    = 2'b11;

    reg [1:0] state = IDLE;
    reg [1:0] next  = IDLE;

    always @(posedge clk or negedge pending) begin
        if (!pending) state = IDLE;
        else state <= next;
    end
    
    always @(*) begin
        next = 2'bxx;
    
        if (!pending) next = IDLE;
        else case (state)
            IDLE:   if (pending && !select) next = PENDING;
                    else next = IDLE;
            
            PENDING: if (select) next = DONE;
                     else next = PENDING;
            
            DONE:    next = DONE;
        endcase
    end

    assign strobe = select && (state === PENDING);
    assign done   = (state === DONE);
endmodule

module timing(
    input clk,

    output phi2,
    output hsync,
    output vsync,
    output irq,

    input res_b,

    input  bus_rw_b,
    output cpu_select,
    output cpu_read_strobe,
    output cpu_write_strobe,
    output io_select,
    input  pi_rw_b,
    output pi_select,
    output pi_read_strobe,
    output pi_write_strobe,
    input  pi_pending,
    output pi_done
);
    reg [18:0] count = 0;
    
    // Bits 9:0 divide 16 MHz 'clk' by 1024 to get the HSync frequency of ~15.6 KHz
    assign hsync = count[9];

    // Bits 18:10 count horizontal scan lines.  Bit 18 is high only momentarily before
    // we reach line 260 and reset the counter.  Therefore we use bit 17 to get a 60 Hz
    // VSync with a duty cycle of ~49.2%.
    
    parameter VBLANK = (19'd260 << 10);
    
    assign vsync = count[17];
    assign irq   = count >= (VBLANK - 32);
    
    always @(posedge clk) begin
        if (count != (VBLANK - 1)) count <= count + 19'd1;
        else count <= 0;
    end

    wire [3:0] strobe = count[3:0];

    assign phi2             = strobe[3];
    assign cpu_select       = strobe == 4'd0 || strobe >= 4'd6;
    assign io_select        = strobe >= 4'd7;
    assign pi_select        = !cpu_select;

    assign cpu_read_strobe  =  bus_rw_b && phi2;
    assign cpu_write_strobe = !bus_rw_b && phi2;

    wire pi_strobe;

    sync pi_sync(
        .clk(clk),
        .select(pi_select),
        .pending(pi_pending),
        .done(pi_done),
        .strobe(pi_strobe)
    );

    assign pi_read_strobe   =  pi_rw_b && pi_strobe;
    assign pi_write_strobe  = !pi_rw_b && pi_strobe;
endmodule

module address_decoding(
    input io_select,
    input [16:0] addr,
    output ram_select,
    output vram_select,
    output pia1_select,
    output pia2_select,
    output via_select,
    output crtc_select,
    output rom_select
);
    parameter RAM  = 0,
              PIA1 = 1,
              PIA2 = 2,
              VIA  = 3,
              CRTC = 4,
              ROM  = 5,
              VRAM = 6;

    reg [6:0] select;

    always @(posedge io_select) begin
        select = 7'b0;

        casex (addr[16:0])
            17'b0_0xxx_xxxx_xxxx_xxxx: select[RAM]  = 1'b1;    // RAM  : 0000-7FFF
            17'b0_1000_xxxx_xxxx_xxxx: select[VRAM] = 1'b1;    // VRAM : 8000-8FFF
            17'b0_1110_1000_0000_xxxx: select[RAM]  = 1'b1;    // CTRL : E80x
            17'b0_1110_1000_0001_xxxx: select[PIA1] = 1'b1;    // PIA1 : E81x
            17'b0_1110_1000_001x_xxxx: select[PIA2] = 1'b1;    // PIA2 : E820-E83F
            17'b0_1110_1000_01xx_xxxx: select[VIA]  = 1'b1;    // VIA  : E840-E87F
            17'b0_1110_1000_1xxx_xxxx: select[CRTC] = 1'b1;    // CRTC : E880-E8FF
            default:                   select[ROM]  = 1'b1;    // ROM  : 9000-E800, E900-FFFF
        endcase
    end

    assign ram_select   = select[RAM];
    assign vram_select  = select[VRAM];
    assign pia1_select  = select[PIA1];
    assign pia2_select  = select[PIA2];
    assign via_select   = select[VIA];
    assign crtc_select  = select[CRTC];
    assign rom_select   = select[ROM];
endmodule

module pi_ctl(
    input pi_write_strobe,
    input [15:0] pi_addr,
    input [7:0] pi_data,
    output res_b,
    output rdy
);
    parameter RES_B = 0,
              RDY   = 1;

    reg [1:0] state = 2'b00;

    always @(negedge pi_write_strobe) begin
        if (pi_addr === 16'hE80F) state <= pi_data[1:0];
    end
    
    assign res_b = state[RES_B];
    assign rdy   = state[RDY];
endmodule

module main (
    // System Bus
    input pi_rw_b,              // RPi 0       : 0 = CPU writing, 1 = CPU reading
    input [15:0] pi_addr,       // RPi 5-19, 1 : Address of requested read/write
    inout [7:0]  pi_data,       // RPi 20-27   : Data bits transfered to/from RPi

    inout bus_rw_b,             // CPU 34          : 0 = CPU writing, 1 = CPU reading
    inout [16:0] bus_addr,      // CPU 9-20, 22-25 : System address bus
    inout [7:0] bus_data,       // CPU 33-26       : System data bus
    
    output [11:10] ram_addr,    // RAM: Intercept A11/A10 to mirror VRAM.  Must remove zero ohm
                                //      resistors at R9 and R10.

    // Timing
    input pi_clk,           // RPi  4 : Clock generated by RPi
    output phi2,            // CPU 37 : 1 MHz cpu clock
    output read_strobe_b,   // RAM 24 : 0 = enabled (oe_b),  1 = High impedance
    output write_strobe_b,  // RAM 29 : 0 = active (we_b),   1 = Not active
    output vsync,

    // CPU
    input  pi_pending_b,    // RPi  2 : (See 'wire' assignment below)
    output pi_done_b,       // RPi  3 : (See 'wire' assignment below)

    inout  cpu_res_b,       // CPU 40 : 0 = reset, 1 = normal operation
    output cpu_rdy,         // CPU  2 : 0 = halt, 1 = run
    inout  cpu_irq_b,       // CPU  4 : 0 = interrupt requested, 1 = normal operation
    inout  cpu_nmi_b,       // CPU  6 : 0 = interrupt reuested, 1 = normal operation
    input  cpu_sync,

    // Address Decoding
    output cpu_be,          // CPU 36 : 1 = High impedance,  0 = enabled (be)
    output ram_ce_b,        // RAM 22 : 0 = enabled (ce_b),  1 = High impedance
    output pia1_cs2_b,
    output pia2_cs2_b,
    output via_cs2_b,
    output io_oe_b,

    input diag,
    input cb2,
    output audio,

    input gfx,
    output hsync,
    output video,
    
    // Reserved by DevBoard (See http://land-boards.com/blwiki/index.php?title=Cyclone_II_EP2C5_Mini_Dev_Board#I.2FO_Pin_Mapping)
    output P3_LED_D2,       // Low to Light LED
    output P7_LED_D4,       // Low to Light LED
    output P9_LED_D5,       // Low to Light LED
    input  P17_50MHz,       // Clock input	
    input  P26_1V2,         // Connected to Vcc 1.2V	Only needed for EP2C8. The "zero ohm" resistor could be removed and the pin used as normal.
    input  P27_GND,         // Connected to GND. Only needed for EP2C8. The "zero ohm" resistor could be removed and the pin used as normal.
    input  P73_POR          // 10uF capacitor to ground. 10K resistor to Vcc, for power up reset if needed?
);
    wire pi_pending = !pi_pending_b;
    wire pi_done;
    assign pi_done_b = !pi_done;
        
    wire cpu_select;
    wire cpu_read_strobe;
    wire cpu_write_strobe;
    wire io_select;
    wire pi_select;
    wire pi_read_strobe;
    wire pi_write_strobe;

    wire res_b;
    wire irq_b = 1'b1;
    wire nmi_b = 1'b1;

    // res_b, irq_b, and nmi_b are open drain for wire-OR (see also *.qsf)
    assign cpu_res_b = res_b ? 1'bZ : 1'b0;
    assign cpu_irq_b = irq_b ? 1'bZ : 1'b0;
    assign cpu_nmi_b = nmi_b ? 1'bZ : 1'b0;

    assign P3_LED_D2 = pi_pending_b;
    assign P7_LED_D4 = pi_done_b;
    assign P9_LED_D5 = !res_b;
    
    wire clk16;     // 16 MHz clock from PLL
    wire clk25;     // 25 MHz clock from PLL
    
    pll pll(
        .inclk0(P17_50MHz),
        .c0(clk16),
        .c1(clk25)
    );
    
    // Timing
    timing timing(
        .clk(clk16),
        .res_b(cpu_res_b),
        .phi2(phi2),
        .bus_rw_b(bus_rw_b),
        .cpu_select(cpu_select),
        .cpu_read_strobe(cpu_read_strobe),
        .cpu_write_strobe(cpu_write_strobe),
        .io_select(io_select),
        .pi_rw_b(pi_rw_b),
        .pi_select(pi_select),
        .pi_read_strobe(pi_read_strobe),
        .pi_write_strobe(pi_write_strobe),
        .pi_pending(pi_pending),
        .pi_done(pi_done)
    );
    
    pi_ctl ctl(
        .pi_write_strobe(pi_write_strobe),
        .pi_addr(pi_addr),
        .pi_data(pi_data),
        .res_b(res_b),
        .rdy(cpu_rdy)
    );
    
    wire pia1_select;
    wire pia2_select;
    wire via_select;
    wire ram_select;
    wire vram_select;
    wire rom_select;
    wire crtc_select;
    
    address_decoding decode0(
        .io_select(io_select),
        .addr(bus_addr),
        .ram_select(ram_select),
        .vram_select(vram_select),
        .pia1_select(pia1_select),
        .pia2_select(pia2_select),
        .via_select(via_select),
        .crtc_select(crtc_select),
        .rom_select(rom_select)
    );

    wire [7:0] pia_data_out;
    wire pia1_oe;
    
    pia1 pia1(
        .addr(bus_addr),
        .data_in(bus_data),
        .data_out(pia_data_out),
        .res_b(cpu_res_b),
        .pi_write_strobe(pi_write_strobe),
        .cpu_read_strobe(cpu_read_strobe),
        .cpu_write_strobe(cpu_write_strobe),
        .oe(pia1_oe)
    );
    
    wire [7:0] crtc_data_out;
    wire crtc_oe;
    
    crtc crtc(
        .cclk(phi2),
        .bus_addr(bus_addr),
        .data_in(bus_data),
        .pi_addr(pi_addr),
        .data_out(crtc_data_out),
        .res_b(cpu_res_b),
        .read_strobe(pi_read_strobe),
        .write_strobe(cpu_write_strobe || pi_write_strobe),
        .crtc_select(crtc_select),
        .hsync(hsync),
        .vsync(vsync)
    );
    
    // Address Decoding
    assign cpu_be   = cpu_select && cpu_rdy;
    wire   pia1_cs  = pia1_select && cpu_be;
    wire   pia2_cs  = pia2_select && cpu_be;
    wire   via_cs   = via_select && cpu_be;
    wire   io_oe    = (pia1_cs && pia1_oe) || pia2_cs || via_cs;

    assign pia1_cs2_b = !pia1_cs;
    assign pia2_cs2_b = !pia2_cs;
    assign via_cs2_b  = !via_cs;
    assign io_oe_b    = !io_oe;

    assign ram_ce_b       = !(ram_select || vram_select || rom_select || !cpu_select);
    wire read_strobe      =  pi_read_strobe || (cpu_read_strobe && cpu_be);
    wire write_strobe     = pi_write_strobe || (cpu_write_strobe && cpu_be && !rom_select);

    assign read_strobe_b  = !read_strobe;
    assign write_strobe_b = !write_strobe;

    reg [7:0] pi_data_reg = 8'hee;

    always @(negedge pi_read_strobe)
        if (pi_addr == 16'he80e) pi_data_reg <= { 7'h0, gfx };
        else if (16'hE8F0 <= pi_addr && pi_addr < 16'hE900) pi_data_reg <= crtc_data_out;
        else pi_data_reg <= bus_data;
    
    assign bus_rw_b = cpu_select
        ? 1'bZ                  // CPU is reading/writing and therefore driving rw_b
        : !pi_write_strobe;     // RPi is reading/writing and therefore driving rw_b
    
    // 40 column PETs have 1KB of video ram, mirrored 4 times.
    // 80 column PETs have 2KB of video ram, mirrored 2 times.
    assign ram_addr[11:10] = pi_select
        ? pi_addr[11:10]            // Give RPi access to full RAM
        : vram_select
            ? 2'b00                 // Mirror VRAM when CPU is reading/writing to $8000-$8FFF
            : bus_addr[11:10];
    
    assign bus_addr = pi_select
        ? {1'b0, pi_addr}       // RPi is reading/writing, and therefore driving addr
        : {1'b0, 16'bZ};        // CPU is reading/writing, and therefore driving addr

    assign pi_data = pi_rw_b
        ? pi_data_reg           // RPi is reading from register
        : 8'bZ;                 // RPi is writing to bus

    assign bus_data =
        pi_write_strobe
            ? pi_data           // RPi is writing, and therefore driving data
            : !pia1_oe          // 0 = data from pia1 is disabled, 1 = normal bus access (including pia1)
                ? pia_data_out  // When PIA1 is not enabled (oe = 0) the FPGA is servicing a read on behalf of the PIA.
                : 8'bZ;         // Is writing and therefore driving data, or CPU/RPi are reading and RAM is driving data

    // Audio
    assign audio = cb2 && diag;

    // Video
    assign video = 1'b0;
endmodule