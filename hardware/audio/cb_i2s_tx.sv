// 12.288 MHz reference -> 3.072 MHz BCLK -> 48 kHz stereo, 32 bits/slot.
// Change SD/WS on BCLK falling edges; receivers sample rising edges. WS changes
// one complete bit before the MSB. PCM16 occupies slot bits 1..16; rest is zero.
module cb_i2s_tx (
    input wire clk, reset,
    input wire [15:0] input_left, input_right,
    input wire input_valid,
    output wire input_ready,
    output reg bclk, ws, sd,
    output reg frame_strobe, frame_valid, started,
    output reg underrun,
    output reg [15:0] underrun_count
);
    reg half_phase;
    reg [5:0] bit_index;
    reg [15:0] frame_left, frame_right;
    assign input_ready=!reset && half_phase && bclk && bit_index==0;
    always @(posedge clk) begin
        if(reset) begin
            half_phase<=0; bit_index<=0; bclk<=0; ws<=1; sd<=0;
            frame_left<=0; frame_right<=0;
            frame_strobe<=0; frame_valid<=0; started<=0;
            underrun<=0; underrun_count<=0;
        end else begin
            frame_strobe<=0;
            half_phase<=!half_phase;
            if(half_phase) begin
                bclk<=!bclk;
                if(bclk) begin
                    bit_index<=bit_index+1'b1;
                    ws<=bit_index[5];
                    sd<=0;
                    if(bit_index==0) begin
                        frame_strobe<=1; frame_valid<=input_valid;
                        frame_left<=input_valid ? input_left:16'b0;
                        frame_right<=input_valid ? input_right:16'b0;
                        if(input_valid) started<=1;
                        else if(started) begin
                            underrun<=1;
                            if(underrun_count!=16'hffff) underrun_count<=underrun_count+1'b1;
                        end
                    end
                    if(bit_index>=1 && bit_index<=16) sd<=frame_left[16-bit_index];
                    if(bit_index>=33 && bit_index<=48) sd<=frame_right[48-bit_index];
                end
            end
        end
    end
endmodule
