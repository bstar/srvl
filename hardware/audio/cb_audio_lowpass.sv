// Original four-pole shift/add smoothing before asynchronous PCM sampling.
// SYS=64 MHz, each pole y += (x-y)/1024, Q16 internal fractions. This is an
// explicitly measured bench response, not an Atari analog-filter model.
module cb_audio_lowpass (
    input wire clk, reset, enable,
    input wire signed [15:0] input_left, input_right,
    output wire signed [15:0] output_left, output_right
);
    reg signed [31:0] left_state[0:3], right_state[0:3];
    wire signed [31:0] target_left={input_left,16'b0}, target_right={input_right,16'b0};
    genvar stage;
    generate for(stage=0;stage<4;stage=stage+1) begin: poles
        wire signed [31:0] previous_left, previous_right;
        if(stage==0) begin: first
            assign previous_left=target_left;
            assign previous_right=target_right;
        end else begin: following
            assign previous_left=left_state[stage-1];
            assign previous_right=right_state[stage-1];
        end
        // The subtraction needs an extra bit at opposite full-scale extremes.
        wire signed [32:0] difference_left={previous_left[31],previous_left}-{left_state[stage][31],left_state[stage]};
        wire signed [32:0] difference_right={previous_right[31],previous_right}-{right_state[stage][31],right_state[stage]};
        wire signed [32:0] step_left=difference_left>>>10, step_right=difference_right>>>10;
        wire signed [32:0] next_left=$signed({left_state[stage][31],left_state[stage]})+step_left;
        wire signed [32:0] next_right=$signed({right_state[stage][31],right_state[stage]})+step_right;
        wire _unused_guard=next_left[32] ^ next_right[32];
        always @(posedge clk) begin
            if(reset || !enable) begin left_state[stage]<=0; right_state[stage]<=0; end
            else begin left_state[stage]<=next_left[31:0]; right_state[stage]<=next_right[31:0]; end
        end
    end endgenerate
    wire signed [32:0] rounded_left={left_state[3][31],left_state[3]}+33'sd32768;
    wire signed [32:0] rounded_right={right_state[3][31],right_state[3]}+33'sd32768;
    wire _unused_fraction=^{rounded_left[32],rounded_left[15:0],rounded_right[32],rounded_right[15:0]};
    assign output_left=enable ? rounded_left[31:16]:16'sd0;
    assign output_right=enable ? rounded_right[31:16]:16'sd0;
endmodule
