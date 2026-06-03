/*
 * SPI Slave Module — Tiny Tapeout (GF26 Shuttle)
 *
 * Tiny Tapeout I/O mapping:
 *   ui_in  [7:0]  — 8 dedicated input pins
 *   uo_out [7:0]  — 8 dedicated output pins
 *   uio_in [7:0]  — bidirectional pins (input path)  [unused here]
 *   uio_out[7:0]  — bidirectional pins (output path) [unused here]
 *   uio_oe [7:0]  — bidirectional pin output-enable   [all 0 = input]
 *
 * SPI pin assignment (ui_in):
 *   ui_in[0] — SCK  (SPI clock, from master)
 *   ui_in[1] — SS   (Slave Select, active-low, from master)
 *   ui_in[2] — MOSI (Master Out Slave In)
 *   ui_in[3..7] — unused inputs (reserved)
 *
 * SPI pin assignment (uo_out):
 *   uo_out[0] — MISO (Master In Slave Out)
 *   uo_out[7:1] — rx_byte[7:0] — last fully received byte, visible on outputs
 *
 * SPI Mode 0 (CPOL=0, CPHA=0):
 *   Data is sampled on the rising edge of SCK.
 *   Data is shifted out on the falling edge of SCK.
 *
 * Protocol:
 *   1. Master asserts SS low to begin a transaction.
 *   2. Master clocks 8 bits MSB-first on MOSI; slave samples on SCK rising edge.
 *   3. Slave simultaneously shifts out tx_byte MSB-first on MISO.
 *   4. After 8 bits, rx_byte holds the received byte; tx_byte reloads.
 *   5. Master de-asserts SS high to end the transaction.
 */

`default_nettype none

module tt_um_spi_slave (
    // Tiny Tapeout standard ports
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // Bidirectional — input path  (unused)
    output wire [7:0] uio_out,  // Bidirectional — output path (unused)
    output wire [7:0] uio_oe,   // Bidirectional — output enable (0 = input)
    input  wire       ena,      // Module enable (tied high by TT framework)
    input  wire       clk,      // System clock (provided by TT framework)
    input  wire       rst_n     // Active-low reset (provided by TT framework)
);

    // -------------------------------------------------------------------------
    // SPI pin aliases
    // -------------------------------------------------------------------------
    wire sck  = ui_in[0];
    wire ss_n = ui_in[1];   // active-low slave select
    wire mosi = ui_in[2];

    // -------------------------------------------------------------------------
    // SCK edge detection — synchronise external SPI clock into system clock
    // -------------------------------------------------------------------------
    reg sck_r1, sck_r2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sck_r1 <= 1'b0;
            sck_r2 <= 1'b0;
        end else begin
            sck_r1 <= sck;
            sck_r2 <= sck_r1;
        end
    end

    wire sck_rising  = ( sck_r1 & ~sck_r2);  // rising  edge of SCK
    wire sck_falling = (~sck_r1 &  sck_r2);  // falling edge of SCK

    // -------------------------------------------------------------------------
    // SS edge detection
    // -------------------------------------------------------------------------
    reg ss_r1, ss_r2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ss_r1 <= 1'b1;
            ss_r2 <= 1'b1;
        end else begin
            ss_r1 <= ss_n;
            ss_r2 <= ss_r1;
        end
    end

    wire ss_falling = (~ss_r1 &  ss_r2);  // SS asserted  (transaction start)
    wire ss_rising  = ( ss_r1 & ~ss_r2);  // SS deasserted (transaction end)
    wire selected   = ~ss_r2;             // high while slave is selected

    // -------------------------------------------------------------------------
    // Shift register and bit counter
    // -------------------------------------------------------------------------
    reg [7:0] shift_reg;    // incoming shift register (MOSI, MSB first)
    reg [7:0] tx_shift;     // outgoing shift register (MISO, MSB first)
    reg [2:0] bit_cnt;      // counts 0–7

    // tx_byte: the byte the slave will send back to the master.
    // For this example, it echoes back the last received byte (loopback).
    // Replace with your own logic as needed.
    reg [7:0] tx_byte;
    reg [7:0] rx_byte;      // last fully received byte

    // -------------------------------------------------------------------------
    // Main SPI state machine (runs in system clock domain)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 8'h00;
            tx_shift  <= 8'h00;
            tx_byte   <= 8'hA5;   // default test pattern
            rx_byte   <= 8'h00;
            bit_cnt   <= 3'd0;
        end else begin

            // --- Transaction start: load TX shift register ---
            if (ss_falling) begin
                tx_shift <= tx_byte;
                bit_cnt  <= 3'd0;
            end

            // --- Rising SCK: sample MOSI ---
            if (sck_rising && selected) begin
                shift_reg <= {shift_reg[6:0], mosi};  // shift in MSB first
                bit_cnt   <= bit_cnt + 3'd1;

                // After 8 bits, latch received byte and reload TX
                if (bit_cnt == 3'd7) begin
                    rx_byte  <= {shift_reg[6:0], mosi};
                    tx_byte  <= {shift_reg[6:0], mosi}; // loopback: echo it back
                end
            end

            // --- Falling SCK: shift out next MISO bit ---
            if (sck_falling && selected) begin
                tx_shift <= {tx_shift[6:0], 1'b0};   // shift out MSB
            end

            // --- Transaction end: optionally reset counter ---
            if (ss_rising) begin
                bit_cnt <= 3'd0;
            end

        end
    end

    // -------------------------------------------------------------------------
    // MISO output — drive only when selected, else tri-state (driven low here
    // as TT has no true Hi-Z on digital outputs; master ignores it when SS=1)
    // -------------------------------------------------------------------------
    wire miso_out = selected ? tx_shift[7] : 1'b0;

    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign uo_out[0]   = miso_out;   // MISO
    assign uo_out[7:1] = rx_byte[7:1]; // Display rx_byte[7:1] on remaining pins
    // Note: rx_byte[0] maps to uo_out[0] position but MISO takes priority there;
    // the full rx_byte is still readable internally and on uo_out[7:1] + MISO.

    // Bidirectional pins all set as inputs (unused)
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

endmodule

