`timescale 1ns/1ps
`default_nettype none

// Test for blocks 2 and 3: write a key and a plaintext through the pins,
// then check the registers inside the wrapper hold exactly those values.
module tb_write;

  reg clk = 0;
  always #10 clk = ~clk;  // 50 MHz

  reg        rst_n  = 0;
  reg  [7:0] ui_in  = 0;
  reg  [7:0] uio_in = 0;
  wire [7:0] uo_out, uio_out, uio_oe;

  tt_um_rj_present dut (
      .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out),
      .uio_oe(uio_oe), .ena(1'b1), .clk(clk), .rst_n(rst_n)
  );

  // One byte write, following the pin rule:
  // set address and data, raise the strobe for 4 clocks, lower it.
  task write_byte(input [4:0] a, input [7:0] d);
    begin
      ui_in  = {3'b000, a};
      uio_in = d;
      repeat (2) @(posedge clk);
      ui_in[7] = 1'b1;
      repeat (4) @(posedge clk);
      ui_in[7] = 1'b0;
      repeat (2) @(posedge clk);
    end
  endtask

  integer i;
  integer starts = 0;
  integer errors = 0;
  always @(posedge clk) if (dut.start_cmd) starts = starts + 1;

  reg [79:0] key = 80'h00112233445566778899;
  reg [63:0] pt  = 64'h0123456789abcdef;

  initial begin
    $dumpfile("block23.vcd");
    $dumpvars(0, tb_write);

    repeat (3) @(posedge clk);
    rst_n = 1;

    // key: address 0x00 gets the most significant byte
    for (i = 0; i < 10; i = i + 1) write_byte(i, key[79 - 8*i -: 8]);
    // plaintext: address 0x0A gets the most significant byte
    for (i = 0; i < 8; i = i + 1)  write_byte(10 + i, pt[63 - 8*i -: 8]);

    // writes to addresses that must not change the registers
    write_byte(5'h12, 8'hAA);  // ciphertext area (read only)
    write_byte(5'h1F, 8'hBB);  // unused address
    write_byte(5'h1A, 8'h00);  // control, bit 0 = 0: no start
    write_byte(5'h1A, 8'h01);  // control, bit 0 = 1: one start

    $display("key_q = %h (expect %h)", dut.key_q, key);
    $display("pt_q  = %h (expect %h)", dut.pt_q, pt);
    $display("start pulses = %0d (expect 1)", starts);
    if (dut.key_q !== key) errors = errors + 1;
    if (dut.pt_q  !== pt)  errors = errors + 1;
    if (starts != 1)       errors = errors + 1;
    if (errors == 0) $display("PASS");
    else             $display("FAIL (%0d checks failed)", errors);
    $finish;
  end

endmodule
