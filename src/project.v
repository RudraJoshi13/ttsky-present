/*
 * Copyright (c) 2026 Rudra Joshi
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny Tapeout wrapper around the PRESENT-80 encryption core
 * by Saied H. Khayat (MIT licence), used unchanged.
 */

`default_nettype none

module tt_um_rj_present (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // Pin names
  wire [4:0] addr  = ui_in[4:0];  // byte address
  wire [7:0] wdata = uio_in;      // byte to write

  // ------------------------------------------------------------
  // Block 1: the strobe on ui_in[7] becomes a one-clock pulse
  // ------------------------------------------------------------
  wire wr_pulse;

  strobe_sync u_sync (
      .clk      (clk),
      .rst_n    (rst_n),
      .strobe_in(ui_in[7]),
      .pulse    (wr_pulse)
  );

  // ------------------------------------------------------------
  // Blocks 2 and 3: on each write pulse, the address picks which
  // byte of the key or plaintext register takes the data byte.
  // Most significant byte at the lowest address.
  // ------------------------------------------------------------
  reg [79:0] key_q;
  reg [63:0] pt_q;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      key_q <= 80'h0;
      pt_q  <= 64'h0;
    end else if (wr_pulse) begin
      case (addr)
        5'h00: key_q[79:72] <= wdata;
        5'h01: key_q[71:64] <= wdata;
        5'h02: key_q[63:56] <= wdata;
        5'h03: key_q[55:48] <= wdata;
        5'h04: key_q[47:40] <= wdata;
        5'h05: key_q[39:32] <= wdata;
        5'h06: key_q[31:24] <= wdata;
        5'h07: key_q[23:16] <= wdata;
        5'h08: key_q[15:8]  <= wdata;
        5'h09: key_q[7:0]   <= wdata;
        5'h0A: pt_q[63:56]  <= wdata;
        5'h0B: pt_q[55:48]  <= wdata;
        5'h0C: pt_q[47:40]  <= wdata;
        5'h0D: pt_q[39:32]  <= wdata;
        5'h0E: pt_q[31:24]  <= wdata;
        5'h0F: pt_q[23:16]  <= wdata;
        5'h10: pt_q[15:8]   <= wdata;
        5'h11: pt_q[7:0]    <= wdata;
        default: ;  // any other address leaves both registers unchanged
      endcase
    end
  end

  // Start command: writing a byte with bit 0 = 1 to address 0x1A.
  wire start_cmd = wr_pulse & (addr == 5'h1A) & wdata[0];

  // ------------------------------------------------------------
  // Block 4: control. A start is accepted only when not busy.
  // The clock edge where start is high is E0.
  // ------------------------------------------------------------
  reg       busy;
  reg       done;
  reg [4:0] cnt;  // counts the round clocks after E0

  wire start = start_cmd & ~busy;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0;
      done <= 1'b0;
      cnt  <= 5'd0;
    end else if (start) begin  // E0: the core loads on this edge
      busy <= 1'b1;
      done <= 1'b0;
      cnt  <= 5'd0;
    end else if (busy) begin
      cnt <= cnt + 5'd1;
      if (cnt == 5'd31) begin  // E32: ciphertext is captured on this edge
        busy <= 1'b0;
        done <= 1'b1;
      end
    end
  end

  // ------------------------------------------------------------
  // The PRESENT core, unchanged.
  // load = not busy: while idle the core keeps reloading the same key
  // and plaintext, so nothing switches. At E0 busy is still 0, so the
  // core loads; then busy goes high, load drops and 31 rounds run.
  // ------------------------------------------------------------
  wire [63:0] core_odat;

  PRESENT_ENCRYPT u_core (
      .odat(core_odat),
      .idat(pt_q),
      .key (key_q),
      .load(~busy),
      .clk (clk)
  );

  // ------------------------------------------------------------
  // Block 5: ciphertext register. Between E31 and E32 the core's
  // output is the ciphertext (for that one clock only), so it is
  // copied at E32, when cnt is 31.
  // ------------------------------------------------------------
  reg [63:0] ct_q;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      ct_q <= 64'h0;
    else if (busy && cnt == 5'd31)
      ct_q <= core_odat;
  end

  // ------------------------------------------------------------
  // Block 6: read multiplexer and output register.
  // The address picks one byte; it appears on uo_out one clock later.
  // ------------------------------------------------------------
  reg [7:0] rdata;

  always @(*) begin
    case (addr)
      5'h00: rdata = key_q[79:72];
      5'h01: rdata = key_q[71:64];
      5'h02: rdata = key_q[63:56];
      5'h03: rdata = key_q[55:48];
      5'h04: rdata = key_q[47:40];
      5'h05: rdata = key_q[39:32];
      5'h06: rdata = key_q[31:24];
      5'h07: rdata = key_q[23:16];
      5'h08: rdata = key_q[15:8];
      5'h09: rdata = key_q[7:0];
      5'h0A: rdata = pt_q[63:56];
      5'h0B: rdata = pt_q[55:48];
      5'h0C: rdata = pt_q[47:40];
      5'h0D: rdata = pt_q[39:32];
      5'h0E: rdata = pt_q[31:24];
      5'h0F: rdata = pt_q[23:16];
      5'h10: rdata = pt_q[15:8];
      5'h11: rdata = pt_q[7:0];
      5'h12: rdata = ct_q[63:56];
      5'h13: rdata = ct_q[55:48];
      5'h14: rdata = ct_q[47:40];
      5'h15: rdata = ct_q[39:32];
      5'h16: rdata = ct_q[31:24];
      5'h17: rdata = ct_q[23:16];
      5'h18: rdata = ct_q[15:8];
      5'h19: rdata = ct_q[7:0];
      5'h1A: rdata = {6'b000000, done, busy};  // status
      5'h1B: rdata = 8'h50;                     // ID: ASCII 'P'
      default: rdata = 8'h00;                   // 0x1C to 0x1F: unused
    endcase
  end

  reg [7:0] rdata_q;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rdata_q <= 8'h00;
    else
      rdata_q <= rdata;
  end

  // ------------------------------------------------------------
  // Outputs
  // ------------------------------------------------------------
  assign uo_out  = rdata_q;
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;  // all uio pins are inputs

  // Pins this design does not use; listed here to avoid lint warnings
  wire _unused = &{ena, ui_in[6:5], 1'b0};

endmodule
