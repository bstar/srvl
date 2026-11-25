// Clock requirements: MS5351 O0=64 MHz, O1=25.2 MHz, O2=12.288 MHz.
// Primitive parameters describe circuitry; no host clock generator is changed.
module gowin_board_clocks (
    input wire sys_ref, video_ref, reset_button,
    output wire sys_clk, sdram_clk, serial_clk, pixel_clk,
    output wire sys_locked, video_locked
);
    rPLL #(.FCLKIN("64.0"),.IDIV_SEL(0),.FBDIV_SEL(0),.ODIV_SEL(8),
           .DYN_IDIV_SEL("false"),.DYN_FBDIV_SEL("false"),.DYN_ODIV_SEL("false"),
           .DYN_DA_EN("false"),.PSDA_SEL("1000"),.DUTYDA_SEL("1000"),
           .CLKFB_SEL("internal"),.DEVICE("GW2A-18C")) system_pll (
        .CLKIN(sys_ref),.RESET(reset_button),.RESET_P(1'b0),.CLKFB(1'b0),
        .FBDSEL(6'b0),.IDSEL(6'b0),.ODSEL(6'b0),.PSDA(4'b0),.DUTYDA(4'b0),.FDLY(4'b0),
        .CLKOUT(sys_clk),.CLKOUTP(sdram_clk),.LOCK(sys_locked),.CLKOUTD(),.CLKOUTD3());
    rPLL #(.FCLKIN("25.2"),.IDIV_SEL(0),.FBDIV_SEL(4),.ODIV_SEL(4),
           .DYN_IDIV_SEL("false"),.DYN_FBDIV_SEL("false"),.DYN_ODIV_SEL("false"),
           .DYN_DA_EN("false"),.PSDA_SEL("0000"),.DUTYDA_SEL("1000"),
           .CLKFB_SEL("internal"),.DEVICE("GW2A-18C")) video_pll (
        .CLKIN(video_ref),.RESET(reset_button),.RESET_P(1'b0),.CLKFB(1'b0),
        .FBDSEL(6'b0),.IDSEL(6'b0),.ODSEL(6'b0),.PSDA(4'b0),.DUTYDA(4'b0),.FDLY(4'b0),
        .CLKOUT(serial_clk),.LOCK(video_locked),.CLKOUTP(),.CLKOUTD(),.CLKOUTD3());
    CLKDIV #(.DIV_MODE("5"),.GSREN("false")) video_divider (
        .HCLKIN(serial_clk),.RESETN(sys_locked && video_locked && !reset_button),
        .CALIB(1'b1),.CLKOUT(pixel_clk));
endmodule
