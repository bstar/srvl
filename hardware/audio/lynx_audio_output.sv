// Portable audio boundary; no board clock generator, I/O or analog circuitry.
module lynx_audio_output (
    input wire clk, reset, enable,
    input wire [15:0] input_left, input_right,
    input wire audio_clk, audio_reset,
    output wire bclk, ws, sd, started, underrun,
    output wire [15:0] underrun_count,
    output wire frame_strobe, frame_valid,
    output wire snapshot_valid,
    output wire [15:0] snapshot_left, snapshot_right,
    output wire [15:0] filtered_left, filtered_right
);
    wire [15:0] held_left, held_right;
    wire held_valid, held_ready;
    cb_audio_lowpass filter (.clk(clk),.reset(reset),.enable(enable),
        .input_left(input_left),.input_right(input_right),.output_left(filtered_left),.output_right(filtered_right));
    cb_stereo_mailbox mailbox (.clk(clk),.reset(reset),.input_left(filtered_left),.input_right(filtered_right),
        .audio_clk(audio_clk),.audio_reset(audio_reset),.output_left(held_left),.output_right(held_right),
        .output_valid(held_valid),.output_ready(held_ready),.snapshot_valid(snapshot_valid),
        .snapshot_left(snapshot_left),.snapshot_right(snapshot_right));
    cb_i2s_tx transmitter (.clk(audio_clk),.reset(audio_reset),.input_left(held_left),.input_right(held_right),
        .input_valid(held_valid),.input_ready(held_ready),.bclk(bclk),.ws(ws),.sd(sd),
        .frame_strobe(frame_strobe),.frame_valid(frame_valid),.started(started),
        .underrun(underrun),.underrun_count(underrun_count));
endmodule
