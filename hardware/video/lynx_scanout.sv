// Legacy 160x102 RGB444 -> exact 320x204 centered on a 640x480/60 transport.
// SYS=64 MHz, VIDEO=25.2 MHz are independent clocks. A one-request mailbox
// transfers stable metadata; two 80-word line buffers alternate ownership.
// Both resets must be asserted together; release each in its own clock domain.
module lynx_scanout #(
    parameter [22:0] FRAME_BASE=23'h100000
) (
    input wire clk, reset,
    input wire video_clk, video_reset,
    input wire display_valid,
    input wire [1:0] display_bank,
    output wire present,
    output wire read_valid,
    input wire read_ready, read_response,
    output wire [22:0] read_address,
    input wire [31:0] read_data,
    output wire [11:0] video_rgb,
    output reg video_de, video_hsync, video_vsync,
    output reg [9:0] video_x, video_y,
    output reg video_frame_valid,
    output reg underrun,
    output reg [15:0] underrun_count,
    output reg protocol_fault
);
    // Only the writer of a bank can modify it. A request for row N+2 is sent
    // after both displayed copies of N have finished, never during its reads.
    (* ram_style="block", no_rw_check=1 *) reg [31:0] lines[0:255];
    reg [31:0] line_word;
    reg sample_odd, sample_valid;
    assign video_rgb=sample_valid ? (sample_odd ? line_word[27:16]:line_word[11:0]):12'b0;
    wire _unused_padding=^{line_word[31:28],line_word[15:12]};

    reg request_toggle, request_frame, request_bank;
    reg [6:0] request_line;
    reg ack_toggle, ack_valid;
    (* ASYNC_REG="TRUE" *) reg request_meta, request_sync;
    (* ASYNC_REG="TRUE" *) reg ack_meta, ack_sync;
    reg seen_request, seen_ack;
    wire mailbox_idle=request_toggle==seen_ack;
    wire new_request=request_sync!=seen_request;
    wire new_ack=ack_sync!=seen_ack;
    always @(posedge clk) begin
        if(reset) begin request_meta<=0; request_sync<=0; end
        else begin request_meta<=request_toggle; request_sync<=request_meta; end
    end
    always @(posedge video_clk) begin
        if(video_reset) begin ack_meta<=0; ack_sync<=0; end
        else begin ack_meta<=ack_toggle; ack_sync<=ack_meta; end
    end

    localparam IDLE=0, PRESENT=1, SNAPSHOT=2, FETCH=3, WAIT=4, ACK=5;
    reg [2:0] state;
    reg frame_valid, fill_bank;
    reg [1:0] frame_bank;
    reg [6:0] fill_line, fill_word;
    assign present=state==PRESENT;
    assign read_valid=state==FETCH;
    assign read_address=FRAME_BASE+{5'b0,frame_bank,16'b0}
                       +23'(fill_line)*23'd320+{14'b0,fill_word,2'b0};
    // Keep RAM data ports free of reset so synthesis can infer block RAM.
    always @(posedge clk)
        if(state==WAIT && read_response) lines[{fill_bank,fill_word}]<=read_data;
    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE; seen_request<=0; ack_toggle<=0; ack_valid<=0;
            frame_valid<=0; frame_bank<=0; fill_bank<=0; fill_line<=0; fill_word<=0;
            protocol_fault<=0;
        end else begin
            if(read_response && state!=WAIT) protocol_fault<=1;
            case(state)
                IDLE: if(new_request) begin
                    // Request metadata has been stable since before the
                    // synchronized toggle, and stays stable until our ACK.
                    seen_request<=request_sync;
                    fill_line<=request_line; fill_bank<=request_bank; fill_word<=0;
                    if(request_frame) state<=PRESENT;
                    else if(frame_valid) state<=FETCH;
                    else begin ack_valid<=0; state<=ACK; end
                end
                PRESENT: state<=SNAPSHOT;
                SNAPSHOT: begin
                    frame_bank<=display_bank; frame_valid<=display_valid;
                    if(display_valid) state<=FETCH;
                    else begin ack_valid<=0; state<=ACK; end
                end
                FETCH: if(read_ready) state<=WAIT;
                WAIT: if(read_response) begin
                    if(fill_word==79) begin ack_valid<=1; state<=ACK; end
                    else begin fill_word<=fill_word+1'b1; state<=FETCH; end
                end
                ACK: begin ack_toggle<=seen_request; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end

    reg [9:0] h_count, v_count;
    reg [1:0] line_valid;
    reg [6:0] line_number[0:1];
    reg [6:0] next_line;
    reg pending_frame, discard_reply, frame_available, pair_valid;
    wire frame_boundary=h_count==0 && v_count==480;
    wire [9:0] canvas_x=h_count-10'd160, canvas_y=v_count-10'd138;
    wire _unused_replication_bits=^{canvas_x[9],canvas_x[0],canvas_y[9:8]};
    wire inside_canvas=h_count>=160 && h_count<480 && v_count>=138 && v_count<342;
    wire [6:0] source_y=canvas_y[7:1];
    wire row_ready=line_valid[source_y[0]] && line_number[source_y[0]]==source_y;
    wire can_prefetch=next_line<2 || (v_count>=138 && v_count<342 &&
                      v_count>=10'd138+({3'b0,next_line}-10'd1)*10'd2);
    always @(posedge video_clk) line_word<=lines[{source_y[0],canvas_x[8:2]}];
    always @(posedge video_clk) begin
        if(video_reset) begin
            h_count<=0; v_count<=0;
            video_x<=0; video_y<=0; video_de<=0; video_hsync<=1; video_vsync<=1;
            sample_odd<=0; sample_valid<=0;
            request_toggle<=0; request_frame<=0; request_bank<=0; request_line<=0; seen_ack<=0;
            line_valid<=0; line_number[0]<=0; line_number[1]<=0;
            next_line<=0; pending_frame<=0; discard_reply<=1;
            frame_available<=0; pair_valid<=0; video_frame_valid<=0; underrun<=0; underrun_count<=0;
        end else begin
            if(h_count==799) begin
                h_count<=0;
                if(v_count==524) v_count<=0; else v_count<=v_count+1'b1;
            end else h_count<=h_count+1'b1;
            video_x<=h_count; video_y<=v_count;
            video_de<=h_count<640 && v_count<480;
            video_hsync<=!(h_count>=656 && h_count<752);
            video_vsync<=!(v_count>=490 && v_count<492);
            sample_odd<=canvas_x[1];
            sample_valid<=inside_canvas && pair_valid && video_frame_valid;

            if(new_ack) begin
                seen_ack<=ack_sync;
                if(!discard_reply && !frame_boundary) begin
                    line_valid[request_bank]<=ack_valid;
                    line_number[request_bank]<=request_line;
                    if(request_frame) frame_available<=ack_valid;
                end
            end
            if(frame_boundary) begin
                // Defer a new frame until any old mailbox operation has ACKed.
                // Ignore late replies from that previous transport frame.
                pending_frame<=1; discard_reply<=1; line_valid<=0;
                frame_available<=0; pair_valid<=0; video_frame_valid<=0; next_line<=0;
            end else if(mailbox_idle) begin
                if(pending_frame) begin
                    request_frame<=1; request_bank<=0; request_line<=0;
                    request_toggle<=!request_toggle;
                    pending_frame<=0; discard_reply<=0; next_line<=1;
                end else if(!discard_reply && next_line<102 && can_prefetch) begin
                    request_frame<=0; request_bank<=next_line[0]; request_line<=next_line;
                    line_valid[next_line[0]]<=0;
                    request_toggle<=!request_toggle; next_line<=next_line+1'b1;
                end
            end
            // Decide once before a source row's two output copies. A late ACK
            // cannot reveal half a row. Underflow blanks the whole pair.
            if(h_count==0 && v_count>=138 && v_count<342 && !canvas_y[0]) begin
                pair_valid<=row_ready;
                if(v_count==138) video_frame_valid<=frame_available && row_ready;
                if(frame_available && !row_ready) begin
                    underrun<=1;
                    if(underrun_count!=16'hffff) underrun_count<=underrun_count+1'b1;
                end
            end
        end
    end
endmodule
