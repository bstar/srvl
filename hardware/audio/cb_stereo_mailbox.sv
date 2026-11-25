// Pull one coherent stereo pair across unrelated clocks. Data stays held in
// the system domain until the next request; only toggles use synchronizers.
// Both resets assert together, then release synchronously to their own clock.
module cb_stereo_mailbox (
    input wire clk, reset,
    input wire [15:0] input_left, input_right,
    input wire audio_clk, audio_reset,
    output reg [15:0] output_left, output_right,
    output reg output_valid,
    input wire output_ready,
    output reg snapshot_valid,
    output reg [15:0] snapshot_left, snapshot_right
);
    reg request_toggle, ack_toggle;
    (* ASYNC_REG="TRUE" *) reg request_meta, request_sync;
    (* ASYNC_REG="TRUE" *) reg ack_meta, ack_sync;
    reg seen_request, waiting;
    always @(posedge clk) begin
        if(reset) begin
            request_meta<=0; request_sync<=0; seen_request<=0; ack_toggle<=0;
            snapshot_valid<=0; snapshot_left<=0; snapshot_right<=0;
        end else begin
            request_meta<=request_toggle; request_sync<=request_meta;
            snapshot_valid<=0;
            if(request_sync!=seen_request) begin
                snapshot_left<=input_left; snapshot_right<=input_right;
                snapshot_valid<=1; seen_request<=request_sync; ack_toggle<=request_sync;
            end
        end
    end
    always @(posedge audio_clk) begin
        if(audio_reset) begin
            ack_meta<=0; ack_sync<=0; request_toggle<=0; waiting<=0;
            output_valid<=0; output_left<=0; output_right<=0;
        end else begin
            ack_meta<=ack_toggle; ack_sync<=ack_meta;
            if(output_ready) output_valid<=0;
            if(!waiting && (!output_valid || output_ready)) begin
                request_toggle<=!request_toggle; waiting<=1;
            end
            if(waiting && ack_sync==request_toggle) begin
                output_left<=snapshot_left; output_right<=snapshot_right;
                output_valid<=1; waiting<=0;
            end
        end
    end
endmodule
