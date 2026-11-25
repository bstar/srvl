// Board primitive wiring. OSER10 serializes D0 first on a 5x DDR clock.
// Physical signal levels/edge quality still require actual-board acceptance.
module gowin_dvi_tx (
    input wire pixel_clk, serial_clk, reset,
    input wire de, hsync, vsync,
    input wire [11:0] rgb,
    output wire clock_p, clock_n,
    output wire [2:0] data_p, data_n
);
    wire [39:0] words;
    wire [3:0] serial;
    cb_dvi_symbols encode (.clk(pixel_clk),.reset(reset),.de(de),.hsync(hsync),.vsync(vsync),
        .rgb(rgb),.symbols(words));
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1) begin: lanes
        OSER10 #(.GSREN("false"),.LSREN("true")) serializer (
            .D0(words[lane*10]),.D1(words[lane*10+1]),.D2(words[lane*10+2]),.D3(words[lane*10+3]),
            .D4(words[lane*10+4]),.D5(words[lane*10+5]),.D6(words[lane*10+6]),.D7(words[lane*10+7]),
            .D8(words[lane*10+8]),.D9(words[lane*10+9]),
            .PCLK(pixel_clk),.FCLK(serial_clk),.RESET(reset),.Q(serial[lane]));
    end endgenerate
    TLVDS_OBUF buffers[3:0] (.I(serial),.O({clock_p,data_p}),.OB({clock_n,data_n}));
endmodule
