// DVI-compatible RGB-only transport. No HDMI audio/data islands are generated.
// RGB444 expands exactly to RGB888; blue carries H/V control during blanking.
module cb_dvi_symbols (
    input wire clk, reset, de, hsync, vsync,
    input wire [11:0] rgb,
    output wire [39:0] symbols
);
    cb_tmds_encoder blue (.clk(clk),.reset(reset),.de(de),.c0(hsync),.c1(vsync),
        .data({rgb[3:0],rgb[3:0]}),.symbol(symbols[9:0]));
    cb_tmds_encoder green (.clk(clk),.reset(reset),.de(de),.c0(1'b0),.c1(1'b0),
        .data({rgb[7:4],rgb[7:4]}),.symbol(symbols[19:10]));
    cb_tmds_encoder red (.clk(clk),.reset(reset),.de(de),.c0(1'b0),.c1(1'b0),
        .data({rgb[11:8],rgb[11:8]}),.symbol(symbols[29:20]));
    assign symbols[39:30]=10'b0000011111;
endmodule
