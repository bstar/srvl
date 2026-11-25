module dvi_encoder_top (
    input wire clk, reset, de, c0, c1,
    input wire [7:0] data,
    input wire rgb_de, hsync, vsync,
    input wire [11:0] rgb,
    output wire [9:0] symbol,
    output wire [39:0] symbols
);
    cb_tmds_encoder single (.clk(clk),.reset(reset),.de(de),.c0(c0),.c1(c1),.data(data),.symbol(symbol));
    cb_dvi_symbols triple (.clk(clk),.reset(reset),.de(rgb_de),.hsync(hsync),.vsync(vsync),.rgb(rgb),.symbols(symbols));
endmodule
