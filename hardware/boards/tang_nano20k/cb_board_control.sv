// Joint reset assertion and local release. The audio activity watchdog mutes
// the amplifier if its independent clock/formatter stops after startup.
module cb_board_control (
    input wire sys_clk, pixel_clk, audio_clk,
    input wire reset_button, sys_locked, video_locked,
    input wire running, audio_ready, audio_underrun, audio_frame_strobe,
    output wire sys_reset, pixel_reset, audio_reset, async_reset,
    output reg audio_alive,
    output wire amplifier_enable
);
    assign async_reset=reset_button || !sys_locked || !video_locked;
    cb_reset_sync reset_sys (.clk(sys_clk),.async_reset(async_reset),.reset(sys_reset));
    cb_reset_sync reset_pixel (.clk(pixel_clk),.async_reset(async_reset),.reset(pixel_reset));
    cb_reset_sync reset_audio (.clk(audio_clk),.async_reset(async_reset),.reset(audio_reset));
    reg audio_toggle;
    always @(posedge audio_clk or posedge audio_reset)
        if(audio_reset) audio_toggle<=0;
        else if(audio_frame_strobe) audio_toggle<=!audio_toggle;
    (* ASYNC_REG="TRUE" *) reg toggle_meta, toggle_sync;
    reg seen_toggle;
    reg [11:0] age;
    always @(posedge sys_clk) begin
        if(sys_reset) begin toggle_meta<=0; toggle_sync<=0; seen_toggle<=0; age<=0; audio_alive<=0; end
        else begin
            toggle_meta<=audio_toggle; toggle_sync<=toggle_meta; seen_toggle<=toggle_sync;
            if(toggle_sync!=seen_toggle) begin age<=0; audio_alive<=1; end
            else if(age!=12'hfff) age<=age+1'b1;
            else audio_alive<=0;
        end
    end
    assign amplifier_enable=!sys_reset && running && audio_ready && !audio_underrun && audio_alive;
endmodule
