// Complete bench-board port: no debug signal is assigned an arbitrary package
// pin. ROM loading and controls use UART; handheld storage/panel remain later.
module lynx_tang_board (
    input wire sys_ref, video_ref, audio_ref, reset_button, uart_rx,
    output wire uart_tx,
    output wire [5:0] led_n,
    output wire sdram_clk, sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n,
    output wire [10:0] sdram_a,
    output wire [1:0] sdram_ba,
    output wire [3:0] sdram_dqm,
    inout wire [31:0] sdram_dq,
    output wire tmds_clock_p, tmds_clock_n,
    output wire [2:0] tmds_data_p, tmds_data_n,
    output wire audio_bclk, audio_ws, audio_sd, amplifier_enable
);
    wire sys_clk, pixel_clk, serial_clk, sys_locked, video_locked;
    wire sys_reset, pixel_reset, audio_reset, async_reset, audio_alive;
    wire [31:0] status, dq_out;
    wire running, dq_oe, video_de, hsync, vsync, audio_frame_strobe;
    wire [11:0] rgb;
    gowin_board_clocks clocks (.sys_ref(sys_ref),.video_ref(video_ref),.reset_button(reset_button),
        .sys_clk(sys_clk),.pixel_clk(pixel_clk),.serial_clk(serial_clk),.sdram_clk(sdram_clk),
        .sys_locked(sys_locked),.video_locked(video_locked));
    cb_board_control control (.sys_clk(sys_clk),.pixel_clk(pixel_clk),.audio_clk(audio_ref),
        .reset_button(reset_button),.sys_locked(sys_locked),.video_locked(video_locked),
        .running(running),.audio_ready(status[13]),.audio_underrun(status[14]),.audio_frame_strobe(audio_frame_strobe),
        .sys_reset(sys_reset),.pixel_reset(pixel_reset),.audio_reset(audio_reset),.async_reset(async_reset),
        .audio_alive(audio_alive),.amplifier_enable(amplifier_enable));
    assign sdram_dq=dq_oe ? dq_out:32'bz;
    wire [13:0] unused_pixel_address;
    wire [11:0] unused_pixel_data;
    wire unused_pixel_write, unused_video_valid, unused_audio_started, unused_audio_underrun;
    wire [9:0] unused_video_x, unused_video_y;
    wire [15:0] unused_video_underruns, unused_audio_left, unused_audio_right, unused_audio_underruns;
    wire unused_audio_frame_valid, unused_audio_snapshot_valid, unused_comlynx;
    wire [15:0] unused_audio_snapshot_left, unused_audio_snapshot_right;
    wire unused_cart_request, unused_cart_ack;
    wire [19:0] unused_cart_address;
    wire [7:0] unused_cart_byte;
    lynx_tang_system #(.VIDEO(1),.AUDIO(1)) system (
        .clk(sys_clk),.reset(sys_reset),.uart_rx(uart_rx),.uart_tx(uart_tx),.status(status),.running(running),
        .video_clk(pixel_clk),.video_reset(pixel_reset),.video_rgb(rgb),.video_de(video_de),.video_hsync(hsync),.video_vsync(vsync),
        .video_frame_valid(unused_video_valid),.video_x(unused_video_x),.video_y(unused_video_y),.video_underruns(unused_video_underruns),
        .pixel_address(unused_pixel_address),.pixel_data(unused_pixel_data),.pixel_write(unused_pixel_write),
        .audio_left(unused_audio_left),.audio_right(unused_audio_right),.audio_clk(audio_ref),.audio_reset(audio_reset),
        .audio_bclk(audio_bclk),.audio_ws(audio_ws),.audio_sd(audio_sd),.audio_started(unused_audio_started),
        .audio_underrun(unused_audio_underrun),.audio_underruns(unused_audio_underruns),
        .audio_frame_strobe(audio_frame_strobe),.audio_frame_valid(unused_audio_frame_valid),
        .audio_snapshot_valid(unused_audio_snapshot_valid),.audio_snapshot_left(unused_audio_snapshot_left),.audio_snapshot_right(unused_audio_snapshot_right),
        .comlynx_tx(unused_comlynx),.cart_request(unused_cart_request),.cart_ack(unused_cart_ack),
        .cart_address(unused_cart_address),.cart_byte(unused_cart_byte),
        .sdram_a(sdram_a),.sdram_ba(sdram_ba),.sdram_dqm(sdram_dqm),.sdram_cke(sdram_cke),.sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),.sdram_cas_n(sdram_cas_n),.sdram_we_n(sdram_we_n),
        .dq_in(sdram_dq),.dq_out(dq_out),.dq_oe(dq_oe));
    gowin_dvi_tx display (.pixel_clk(pixel_clk),.serial_clk(serial_clk),.reset(pixel_reset),
        .de(video_de),.hsync(hsync),.vsync(vsync),.rgb(rgb),
        .clock_p(tmds_clock_p),.clock_n(tmds_clock_n),.data_p(tmds_data_p),.data_n(tmds_data_n));
    reg [25:0] heartbeat;
    always @(posedge sys_clk) if(sys_reset) heartbeat<=0; else heartbeat<=heartbeat+1'b1;
    wire fault=|{status[14],status[12:9],status[5]} || (status[13] && !audio_alive);
    assign led_n=~{heartbeat[25],status[13],status[8],running,status[0],fault};
    wire _unused_reset=async_reset;
endmodule
