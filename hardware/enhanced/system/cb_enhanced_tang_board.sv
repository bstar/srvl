// Tang Nano 20K bench top for the enhanced console skeleton. It reuses the
// legacy board's clock wrapper, reset synchronizer, DVI transmitter and pin
// manifest. The CPU/memory clock is a real divided clock, not a gated one.
// Untested on hardware: clock-divider phase, SDRAM I/O timing and the
// serializer remain as unqualified here as they are for the legacy board.
module cb_enhanced_tang_board #(
    parameter ROM_FILE="enhanced-demo.hex"
) (
    input wire sys_ref, video_ref, reset_button,
    output wire [5:0] led_n,
    output wire sdram_clk, sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n,
    output wire [10:0] sdram_a,
    output wire [1:0] sdram_ba,
    output wire [3:0] sdram_dqm,
    inout wire [31:0] sdram_dq,
    output wire tmds_clock_p, tmds_clock_n,
    output wire [2:0] tmds_data_p, tmds_data_n
);
    wire sys_clk, pixel_clk, serial_clk, memory_clk, sys_locked, video_locked;
    gowin_board_clocks clocks (.sys_ref(sys_ref),.video_ref(video_ref),.reset_button(reset_button),
        .sys_clk(sys_clk),.pixel_clk(pixel_clk),.serial_clk(serial_clk),.sdram_clk(sdram_clk),
        .sys_locked(sys_locked),.video_locked(video_locked));
    // 64 MHz / 8 = 8 MHz CPU and local-memory clock.
    CLKDIV #(.DIV_MODE("8"),.GSREN("false")) cpu_divider (
        .HCLKIN(sys_clk),.RESETN(sys_locked && !reset_button),.CALIB(1'b1),.CLKOUT(memory_clk));
    wire async_reset=reset_button || !sys_locked || !video_locked;
    wire sys_reset, pixel_reset;
    cb_reset_sync reset_sys (.clk(sys_clk),.async_reset(async_reset),.reset(sys_reset));
    cb_reset_sync reset_pixel (.clk(pixel_clk),.async_reset(async_reset),.reset(pixel_reset));

    wire [31:0] dq_out;
    wire dq_oe, video_de, hsync, vsync;
    wire [11:0] rgb;
    wire [7:0] diagnostic;
    wire initialized, protocol_fault, ownership_fault, underrun, display_bank;
    wire [9:0] unused_video_x, unused_video_y;
    wire unused_frame_valid;
    assign sdram_dq=dq_oe ? dq_out:32'bz;
    cb_enhanced_system #(.ROM_FILE(ROM_FILE)) system (
        .clk(sys_clk),.reset(sys_reset),.memory_clk(memory_clk),
        .video_clk(pixel_clk),.video_reset(pixel_reset),
        .video_rgb(rgb),.video_de(video_de),.video_hsync(hsync),.video_vsync(vsync),
        .video_x(unused_video_x),.video_y(unused_video_y),.video_frame_valid(unused_frame_valid),
        .diagnostic(diagnostic),.initialized(initialized),.protocol_fault(protocol_fault),
        .ownership_fault(ownership_fault),.underrun(underrun),.display_bank(display_bank),
        .sdram_a(sdram_a),.sdram_ba(sdram_ba),.sdram_dqm(sdram_dqm),.sdram_cke(sdram_cke),.sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),.sdram_cas_n(sdram_cas_n),.sdram_we_n(sdram_we_n),
        .dq_in(sdram_dq),.dq_out(dq_out),.dq_oe(dq_oe));
    gowin_dvi_tx display (.pixel_clk(pixel_clk),.serial_clk(serial_clk),.reset(pixel_reset),
        .de(video_de),.hsync(hsync),.vsync(vsync),.rgb(rgb),
        .clock_p(tmds_clock_p),.clock_n(tmds_clock_n),.data_p(tmds_data_p),.data_n(tmds_data_n));
    reg [25:0] heartbeat;
    always @(posedge sys_clk) if(sys_reset) heartbeat<=0; else heartbeat<=heartbeat+1'b1;
    // LEDs: heartbeat, SDRAM ready, displayed surface, frame counter bit,
    // CPU-reported failure, hardware fault.
    wire fault=protocol_fault || ownership_fault || underrun;
    wire _unused_diagnostic=^diagnostic[4:0];
    assign led_n=~{heartbeat[25],initialized,display_bank,diagnostic[5],diagnostic==8'he0,fault};
endmodule
