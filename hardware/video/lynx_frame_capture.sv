// Three-bank capture of the original console's emitted RGB samples. A bank is
// publishable only after its complete ordered source frame AND all write ACKs.
// The caller asserts present at a safe scanout boundary after old reads drain.
// All signals here share clk; the pixel-domain mailbox/line reader is separate.
module lynx_frame_capture #(
    parameter integer PIXELS=16320,
    parameter [22:0] FRAME_BASE=23'h100000
) (
    input wire clk, reset, enable,
    input wire pixel_write,
    input wire [13:0] pixel_address,
    input wire [11:0] pixel_data,
    input wire present,
    output reg display_valid,
    output reg [1:0] display_bank,
    output reg frame_ready,
    output reg overflow, capture_error,
    output reg [15:0] dropped_frames,
    output wire write_valid,
    input wire write_ready, write_response,
    output wire [22:0] write_address,
    output wire [31:0] write_data,
    output wire [3:0] write_mask
);
    localparam FREE=0, WRITING=1, DRAIN=2, READY=3, DISPLAY=4;
    reg [2:0] bank_state[0:2];
    reg candidate_valid[0:2];
    reg [9:0] pending[0:2];
    reg source_active, busy;
    reg [1:0] source_bank, ready_bank, issued_bank;
    reg [13:0] expected_address;
    reg free_found, retire_found;
    reg [1:0] free_bank, retire_bank;
    integer i;
    always @* begin
        free_found=0; free_bank=0; retire_found=0; retire_bank=0;
        for(integer b=0;b<3;b=b+1) begin
            if(!free_found && bank_state[b]==FREE) begin free_found=1; free_bank=2'(b); end
            if(!retire_found && bank_state[b]==DRAIN && pending[b]==0 && candidate_valid[b]) begin
                retire_found=1; retire_bank=2'(b);
            end
        end
    end
    wire start=enable && pixel_write && pixel_address==0;
    wire sequence_ok=start ? free_found:(source_active && pixel_address==expected_address && {1'b0,pixel_address}<15'(PIXELS));
    wire [1:0] enqueue_bank=start ? free_bank:source_bank;
    wire queue_ready, queue_valid;
    wire [31:0] queue_data;
    wire [8:0] unused_queue_level;
    wire enqueue=enable && pixel_write && sequence_ok && queue_ready;
    wire abort_old=source_active && (!enable || start);
    wire drop_new=start && !enqueue;
    wire drop_partial=enable && pixel_write && !start && source_active && !enqueue;
    wire [1:0] drop_increment={1'b0,abort_old}+{1'b0,drop_new}+{1'b0,drop_partial};
    cb_sync_fifo queue (.clk(clk),.reset(reset),.input_valid(enable && pixel_write && sequence_ok),
        .input_ready(queue_ready),.input_data({4'b0,enqueue_bank,pixel_address,pixel_data}),
        .output_valid(queue_valid),.output_ready(write_ready && !busy),
        .output_data(queue_data),.level(unused_queue_level));
    wire _unused_padding=^queue_data[31:28];
    assign write_valid=queue_valid && !busy;
    assign write_address=FRAME_BASE+{5'b0,queue_data[27:26],16'b0}+{8'b0,queue_data[25:12],1'b0};
    assign write_data={4'b0,queue_data[11:0],4'b0,queue_data[11:0]};
    assign write_mask=queue_data[12] ? 4'b1100:4'b0011;
    always @(posedge clk) begin
        if(reset) begin
            display_valid<=0; display_bank<=0; frame_ready<=0;
            source_active<=0; source_bank<=0; expected_address<=0;
            ready_bank<=0; issued_bank<=0; busy<=0;
            overflow<=0; capture_error<=0; dropped_frames<=0;
            for(i=0;i<3;i=i+1) begin bank_state[i]<=FREE; pending[i]<=0; candidate_valid[i]<=0; end
        end else begin
            if(dropped_frames>16'hffff-{14'b0,drop_increment}) dropped_frames<=16'hffff;
            else dropped_frames<=dropped_frames+{14'b0,drop_increment};
            if(write_response) begin
                if(busy) busy<=0;
                else capture_error<=1;
            end
            if(write_valid && write_ready) begin busy<=1; issued_bank<=queue_data[27:26]; end
            for(i=0;i<3;i=i+1) begin
                case({enqueue && enqueue_bank==2'(i),write_response && busy && issued_bank==2'(i)})
                    2'b10: pending[i]<=pending[i]+1'b1;
                    2'b01: if(pending[i]!=0) pending[i]<=pending[i]-1'b1; else capture_error<=1;
                    default: begin end
                endcase
            end
            // Present the previous ready bank first. A simultaneous new
            // completion becomes the next READY bank instead of being lost.
            if(present && frame_ready) begin
                if(display_valid) bank_state[display_bank]<=FREE;
                bank_state[ready_bank]<=DISPLAY; display_bank<=ready_bank;
                display_valid<=1; frame_ready<=0;
            end
            for(i=0;i<3;i=i+1)
                if(bank_state[i]==DRAIN && pending[i]==0 && !candidate_valid[i]) bank_state[i]<=FREE;
            if(retire_found) begin
                if(frame_ready && !present) bank_state[ready_bank]<=FREE;
                bank_state[retire_bank]<=READY; ready_bank<=retire_bank; frame_ready<=1;
            end
            if(!enable && source_active) begin
                source_active<=0; bank_state[source_bank]<=DRAIN; candidate_valid[source_bank]<=0;
            end
            if(enable && pixel_write) begin
                if(start) begin
                    if(source_active) begin
                        bank_state[source_bank]<=DRAIN; candidate_valid[source_bank]<=0;
                        capture_error<=1;
                    end
                    source_active<=0;
                    if(enqueue) begin
                        source_bank<=free_bank; expected_address<=1; source_active<=PIXELS!=1;
                        bank_state[free_bank]<=PIXELS==1 ? DRAIN:WRITING; candidate_valid[free_bank]<=1;
                    end else begin
                        if(!queue_ready) overflow<=1;
                    end
                end else if(source_active) begin
                    if(!enqueue) begin
                        source_active<=0; bank_state[source_bank]<=DRAIN; candidate_valid[source_bank]<=0;
                        if(!queue_ready) overflow<=1; else capture_error<=1;
                    end else begin
                        expected_address<=expected_address+1'b1;
                        if(pixel_address==14'(PIXELS-1)) begin source_active<=0; bank_state[source_bank]<=DRAIN; end
                    end
                end
            end
        end
    end
endmodule
