`timescale 1ns/1ps
`default_nettype none

// Test for block 1: two strobes of different lengths must give
// exactly two pulses, each one clock long.
module tb_strobe_sync;

  reg clk = 0;
  always #10 clk = ~clk;  // 20 ns period = 50 MHz, rising edges at 10, 30, 50 ... ns

  reg  rst_n = 0;
  reg  strobe_in = 0;
  wire pulse;

  strobe_sync dut (.clk(clk), .rst_n(rst_n), .strobe_in(strobe_in), .pulse(pulse));

  integer pulses = 0;       // how many times pulse went high
  integer high_clocks = 0;  // how many clock edges saw pulse high

  always @(posedge pulse) pulses = pulses + 1;
  always @(posedge clk) if (pulse) high_clocks = high_clocks + 1;

  initial begin
    $dumpfile("block1.vcd");
    $dumpvars(0, tb_strobe_sync);

    #45  rst_n = 1;      // release reset at 45 ns
    #37  strobe_in = 1;  // 82 ns: rises between clock edges on purpose
    #80  strobe_in = 0;  // held 4 clocks
    #100 strobe_in = 1;  // second strobe
    #200 strobe_in = 0;  // held 10 clocks
    #100;

    $display("pulses = %0d (expect 2), clocks with pulse high = %0d (expect 2)", pulses, high_clocks);
    if (pulses == 2 && high_clocks == 2) $display("PASS");
    else                                 $display("FAIL");
    $finish;
  end

endmodule
