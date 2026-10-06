`timescale 1ns/1ps
`default_nettype none

// Test for block 6, and the whole wrapper end to end: everything goes
// through the pins only. Write key and plaintext, start, poll the status
// byte, read the ciphertext back on uo_out. Also read back the key,
// plaintext, ID byte and an unused address.
module tb_read;

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

  // One byte read, following the pin rule:
  // set the address, wait 2 clocks, read uo_out.
  task read_byte(input [4:0] a, output [7:0] d);
    begin
      ui_in = {3'b000, a};
      repeat (2) @(posedge clk);
      #1 d = uo_out;
    end
  endtask

  integer i;
  integer errors = 0;
  reg [7:0]  b;
  reg [79:0] key_rd;
  reg [63:0] pt_rd, ct_rd;

  task encrypt_check(input [63:0] pt, input [79:0] key, input [63:0] expect_ct);
    begin
      for (i = 0; i < 10; i = i + 1) write_byte(i, key[79 - 8*i -: 8]);
      for (i = 0; i < 8; i = i + 1)  write_byte(10 + i, pt[63 - 8*i -: 8]);

      // read the key and plaintext back through uo_out
      for (i = 0; i < 10; i = i + 1) begin read_byte(i, b);      key_rd = {key_rd[71:0], b}; end
      for (i = 0; i < 8; i = i + 1)  begin read_byte(10 + i, b); pt_rd  = {pt_rd[55:0], b};  end
      if (key_rd !== key) begin errors = errors + 1; $display("key readback %h WRONG", key_rd); end
      if (pt_rd  !== pt)  begin errors = errors + 1; $display("pt readback %h WRONG", pt_rd); end

      write_byte(5'h1A, 8'h01);                 // start
      b = 8'h00;
      while (b !== 8'h02) read_byte(5'h1A, b);  // poll status until done=1, busy=0

      for (i = 0; i < 8; i = i + 1) begin read_byte(18 + i, b); ct_rd = {ct_rd[55:0], b}; end
      $display("pt=%h key=%h  read ct=%h  expect=%h  %s", pt, key, ct_rd, expect_ct,
               (ct_rd === expect_ct) ? "OK" : "WRONG");
      if (ct_rd !== expect_ct) errors = errors + 1;
    end
  endtask

  initial begin
    $dumpfile("block6.vcd");
    $dumpvars(0, tb_read);

    repeat (3) @(posedge clk);
    rst_n = 1;

    // after reset: ID reads 0x50, status reads 0, ciphertext reads 0
    read_byte(5'h1B, b); $display("ID = %h (expect 50)", b);     if (b !== 8'h50) errors = errors + 1;
    read_byte(5'h1A, b); $display("status = %h (expect 00)", b); if (b !== 8'h00) errors = errors + 1;
    read_byte(5'h12, b); $display("ct[63:56] = %h (expect 00)", b); if (b !== 8'h00) errors = errors + 1;

    encrypt_check(64'h0000000000000000, 80'h00000000000000000000, 64'h5579c1387b228445);
    encrypt_check(64'h0000000000000000, 80'hffffffffffffffffffff, 64'he72c46c0f5945049);
    encrypt_check(64'hffffffffffffffff, 80'h00000000000000000000, 64'ha112ffc72f68417b);
    encrypt_check(64'hffffffffffffffff, 80'hffffffffffffffffffff, 64'h3333dcd3213210d2);

    read_byte(5'h1F, b); $display("unused 0x1F = %h (expect 00)", b); if (b !== 8'h00) errors = errors + 1;

    if (errors == 0) $display("PASS");
    else             $display("FAIL (%0d checks failed)", errors);
    $finish;
  end

endmodule
