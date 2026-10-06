`timescale 1ns/1ps
`default_nettype none

// Test for blocks 4 and 5: encrypt the four official PRESENT-80 vectors
// through the pins and check the ciphertext register, the busy time,
// and that a start while busy is ignored.
module tb_encrypt;

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

  integer i, v;
  integer errors = 0;
  integer busy_clocks;

  // write key and plaintext, start, wait for done, check the result
  task encrypt_check(input [63:0] pt, input [79:0] key, input [63:0] expect_ct);
    begin
      for (i = 0; i < 10; i = i + 1) write_byte(i, key[79 - 8*i -: 8]);
      for (i = 0; i < 8; i = i + 1)  write_byte(10 + i, pt[63 - 8*i -: 8]);
      write_byte(5'h1A, 8'h01);  // start
      while (!dut.done) @(posedge clk);
      $display("pt=%h key=%h  ct_q=%h  expect=%h  %s", pt, key, dut.ct_q, expect_ct,
               (dut.ct_q === expect_ct) ? "OK" : "WRONG");
      if (dut.ct_q !== expect_ct) errors = errors + 1;
    end
  endtask

  // count how many clock edges see busy high, for one encryption
  always @(posedge clk) if (dut.busy) busy_clocks = busy_clocks + 1;

  initial begin
    $dumpfile("block45.vcd");
    $dumpvars(0, tb_encrypt);

    repeat (3) @(posedge clk);
    rst_n = 1;

    // the four official vectors (PRESENT paper, Appendix I)
    encrypt_check(64'h0000000000000000, 80'h00000000000000000000, 64'h5579c1387b228445);
    encrypt_check(64'h0000000000000000, 80'hffffffffffffffffffff, 64'he72c46c0f5945049);
    encrypt_check(64'hffffffffffffffff, 80'h00000000000000000000, 64'ha112ffc72f68417b);
    encrypt_check(64'hffffffffffffffff, 80'hffffffffffffffffffff, 64'h3333dcd3213210d2);

    // busy must last exactly 32 clocks
    busy_clocks = 0;
    write_byte(5'h1A, 8'h01);
    while (!dut.done) @(posedge clk);
    @(posedge clk);
    $display("busy lasted %0d clocks (expect 32)", busy_clocks);
    if (busy_clocks != 32) errors = errors + 1;

    // a start while busy must be ignored: start, then change the
    // plaintext and start again while still busy
    write_byte(5'h1A, 8'h01);          // start with pt = all ones, key = all ones
    write_byte(5'h11, 8'h00);          // change the last plaintext byte while busy
    write_byte(5'h1A, 8'h01);          // this start must be ignored
    while (!dut.done) @(posedge clk);
    $display("after start-while-busy: ct_q=%h (expect 3333dcd3213210d2) %s", dut.ct_q,
             (dut.ct_q === 64'h3333dcd3213210d2) ? "OK" : "WRONG");
    if (dut.ct_q !== 64'h3333dcd3213210d2) errors = errors + 1;

    if (errors == 0) $display("PASS");
    else             $display("FAIL (%0d checks failed)", errors);
    $finish;
  end

endmodule
