`default_nettype none

// Block 1: turns the write strobe from a pin (not timed to clk)
// into a pulse that is high for exactly one clock.
module strobe_sync (
    input  wire clk,
    input  wire rst_n,      // active-low reset
    input  wire strobe_in,  // from ui_in[7]
    output wire pulse       // one clock high per rising edge of strobe_in
);

  reg s1, s2, s3;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1 <= 1'b0;
      s2 <= 1'b0;
      s3 <= 1'b0;
    end else begin
      s1 <= strobe_in;  // first flop: may be briefly unsettled
      s2 <= s1;         // second flop: settled, safe to use
      s3 <= s2;         // s2 one clock ago
    end
  end

  assign pulse = s2 & ~s3;  // s2 is 1 now and was 0 one clock ago

endmodule
