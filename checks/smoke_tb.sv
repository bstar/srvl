`timescale 1ns/1ps
module smoke_tb;
  reg [7:0] a, b;
  wire [8:0] sum;
  smoke dut(a, b, sum);
  initial begin
    a = 8'd255; b = 8'd1;
    #1;
    if (sum !== 9'd256) $fatal(1, "carry lost");
    a = 8'd7; b = 8'd9;
    #1;
    if (sum !== 9'd16) $fatal(1, "addition failed");
    $finish;
  end
endmodule
