`timescale 1ns/1ps
module smoke(input wire [7:0] a, b, output wire [8:0] sum);
  assign sum = {1'b0, a} + {1'b0, b};
endmodule
