// Native 320x204 indexed surface -> exact 2x (640x408) centered on a
// 640x480/60 transport. Derived from this project's legacy scanout: SYS and
// VIDEO are independent clocks, a one-request mailbox transfers stable
// metadata, and two 160-word line buffers alternate ownership.
// A surface word holds two 16-bit pixels: coverage in bit 12, band in 11:8,
// palette index in 7:0. Each pixel is merged with the two tile planes as the
// line is filled, so the line buffer holds final palette indices:
//   front plane, unless the object pixel is covered with band >= 8
//   covered object pixel
//   back plane
//   otherwise uncovered, shown black
// The 256-entry RGB444 palette is written from its own clock and read in the
// video domain.
// Both resets must be asserted together; release each in its own clock domain.
module cb_native_scanout #(
    parameter [22:0] SURFACE_BASE=23'h100000
) (
    input wire clk, reset,
    input wire video_clk, video_reset,
    input wire display_valid,
    input wire display_bank,
    output wire present,
    output wire read_valid,
    input wire read_ready, read_response,
    output wire [22:0] read_address,
    input wire [31:0] read_data,
    // Tile-plane pixel stream for the row being filled; see cb_tile_planes.
    output wire tile_start,
    output wire [7:0] tile_line,
    input wire tile_valid,
    output wire tile_take,
    input wire [8:0] tile_back, tile_front,
    input wire palette_clk, palette_write,
    input wire [7:0] palette_index,
    input wire [11:0] palette_rgb,
    output wire [11:0] video_rgb,
    output reg video_de, video_hsync, video_vsync,
    output reg [9:0] video_x, video_y,
    output reg video_frame_valid,
    output reg underrun,
    output reg [15:0] underrun_count,
    output reg protocol_fault
);
    localparam [9:0] TOP=10'd36, BOTTOM=10'd444;
    localparam [7:0] LAST_ROW=8'd203, LAST_WORD=8'd159;
    // Only the writer of a bank can modify it. A request for row N+2 is sent
    // after both displayed copies of N have finished, never during its reads.
    (* ram_style="block", no_rw_check=1 *) reg [31:0] lines[0:511];
    (* ram_style="block", no_rw_check=1 *) reg [11:0] palette[0:255];
    reg [31:0] line_word;
    reg [11:0] palette_word;
    reg sample_odd, sample_valid, pixel_valid;
    wire [15:0] sample=sample_odd ? line_word[31:16]:line_word[15:0];
    wire _unused_sample=^{sample[15:13],sample[11:8]};   // always zero after composition
    assign video_rgb=pixel_valid ? palette_word:12'b0;
    always @(posedge palette_clk) if(palette_write) palette[palette_index]<=palette_rgb;

    reg request_toggle, request_frame, request_bank;
    reg [7:0] request_line;
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

    localparam IDLE=0, PRESENT=1, SNAPSHOT=2, START=3, FETCH=4, WAIT=5, LOW=6, HIGH=7, ACK=8;
    reg [3:0] state;
    reg [31:0] object;
    reg [15:0] low;
    wire _unused_object=^{object[31:29],object[26:24],object[15:13],object[10:8]};
    function automatic [15:0] compose(input object_covered, input above, input [7:0] object_index);
        reg covered;
        reg [7:0] index;
        begin
            covered=1'b1;
            if(tile_front[8] && !(object_covered && above)) index=tile_front[7:0];
            else if(object_covered) index=object_index;
            else if(tile_back[8]) index=tile_back[7:0];
            else begin covered=1'b0; index=8'b0; end
            compose={3'b0,covered,4'b0,index};
        end
    endfunction
    assign tile_start=state==START;
    assign tile_line=fill_line;
    assign tile_take=tile_valid && (state==LOW || state==HIGH);
    reg frame_valid, frame_bank, fill_bank;
    reg [7:0] fill_line, fill_word;
    assign present=state==PRESENT;
    assign read_valid=state==FETCH;
    assign read_address=SURFACE_BASE+{4'b0,frame_bank,18'b0}
                       +23'(fill_line)*23'd640+{13'b0,fill_word,2'b0};
    // Keep RAM data ports free of reset so synthesis can infer block RAM.
    always @(posedge clk)
        if(state==HIGH && tile_valid) lines[{fill_bank,fill_word}]<={compose(object[28],object[27],object[23:16]),low};
    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE; seen_request<=0; ack_toggle<=0; ack_valid<=0;
            frame_valid<=0; frame_bank<=0; fill_bank<=0; fill_line<=0; fill_word<=0;
            protocol_fault<=0; object<=0; low<=0;
        end else begin
            if(read_response && state!=WAIT) protocol_fault<=1;
            case(state)
                IDLE: if(new_request) begin
                    // Request metadata has been stable since before the
                    // synchronized toggle, and stays stable until our ACK.
                    seen_request<=request_sync;
                    fill_line<=request_line; fill_bank<=request_bank; fill_word<=0;
                    if(request_frame) state<=PRESENT;
                    else if(frame_valid) state<=START;
                    else begin ack_valid<=0; state<=ACK; end
                end
                // The frame owner may change the front bank during PRESENT;
                // SNAPSHOT then holds it for every row of this transport frame.
                PRESENT: state<=SNAPSHOT;
                SNAPSHOT: begin
                    frame_bank<=display_bank; frame_valid<=display_valid;
                    if(display_valid) state<=START;
                    else begin ack_valid<=0; state<=ACK; end
                end
                // The planes latch this row and their scroll values here,
                // after the frame owner has applied them at PRESENT.
                START: state<=FETCH;
                FETCH: if(read_ready) state<=WAIT;
                WAIT: if(read_response) begin object<=read_data; state<=LOW; end
                LOW: if(tile_valid) begin low<=compose(object[12],object[11],object[7:0]); state<=HIGH; end
                HIGH: if(tile_valid) begin
                    if(fill_word==LAST_WORD) begin ack_valid<=1; state<=ACK; end
                    else begin fill_word<=fill_word+1'b1; state<=FETCH; end
                end
                ACK: begin ack_toggle<=seen_request; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end

    reg [9:0] h_count, v_count;
    reg [1:0] line_valid;
    reg [7:0] line_number[0:1];
    reg [7:0] next_line;
    reg pending_frame, discard_reply, frame_available, pair_valid;
    reg stage_de, stage_hsync, stage_vsync;
    reg [9:0] stage_x, stage_y;
    wire frame_boundary=h_count==0 && v_count==480;
    wire [9:0] canvas_y=v_count-TOP;
    wire _unused_replication_bits=^{h_count[0],canvas_y[9:2],canvas_y[0]};
    wire inside_canvas=h_count<640 && v_count>=TOP && v_count<BOTTOM;
    wire display_buffer=canvas_y[1];
    // The canvas starts at the first pixel of a line, so a row's validity is
    // decided on the last pixel clock of the line before it.
    wire [9:0] next_canvas_y=v_count+10'd1-TOP;
    wire [7:0] next_source_y=next_canvas_y[8:1];
    wire _unused_next_canvas=next_canvas_y[9];
    wire next_pair_start=h_count==799 && v_count>=TOP-10'd1 && v_count<BOTTOM-10'd1 && !next_canvas_y[0];
    wire row_ready=line_valid[next_source_y[0]] && line_number[next_source_y[0]]==next_source_y;
    wire can_prefetch=next_line<2 || (v_count>=TOP && v_count<BOTTOM &&
                      v_count>=TOP+({2'b0,next_line}-10'd1)*10'd2);
    always @(posedge video_clk) begin
        line_word<=lines[{display_buffer,h_count[9:2]}];
        palette_word<=palette[sample[7:0]];
    end
    always @(posedge video_clk) begin
        if(video_reset) begin
            h_count<=0; v_count<=0;
            video_x<=0; video_y<=0; video_de<=0; video_hsync<=1; video_vsync<=1;
            stage_x<=0; stage_y<=0; stage_de<=0; stage_hsync<=1; stage_vsync<=1;
            sample_odd<=0; sample_valid<=0; pixel_valid<=0;
            request_toggle<=0; request_frame<=0; request_bank<=0; request_line<=0; seen_ack<=0;
            line_valid<=0; line_number[0]<=0; line_number[1]<=0;
            next_line<=0; pending_frame<=0; discard_reply<=1;
            frame_available<=0; pair_valid<=0; video_frame_valid<=0; underrun<=0; underrun_count<=0;
        end else begin
            if(h_count==799) begin
                h_count<=0;
                if(v_count==524) v_count<=0; else v_count<=v_count+1'b1;
            end else h_count<=h_count+1'b1;
            // Stage 1 accompanies the line-buffer word, stage 2 the palette word.
            stage_x<=h_count; stage_y<=v_count;
            stage_de<=h_count<640 && v_count<480;
            stage_hsync<=!(h_count>=656 && h_count<752);
            stage_vsync<=!(v_count>=490 && v_count<492);
            sample_odd<=h_count[1];
            sample_valid<=inside_canvas && pair_valid && video_frame_valid;
            video_x<=stage_x; video_y<=stage_y;
            video_de<=stage_de; video_hsync<=stage_hsync; video_vsync<=stage_vsync;
            pixel_valid<=sample_valid && sample[12];

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
                end else if(!discard_reply && next_line<=LAST_ROW && can_prefetch) begin
                    request_frame<=0; request_bank<=next_line[0]; request_line<=next_line;
                    line_valid[next_line[0]]<=0;
                    request_toggle<=!request_toggle; next_line<=next_line+1'b1;
                end
            end
            // Decide once before a source row's two output copies. A late ACK
            // cannot reveal half a row. Underflow blanks the whole pair.
            if(next_pair_start) begin
                pair_valid<=row_ready;
                if(v_count==TOP-10'd1) video_frame_valid<=frame_available && row_ready;
                if(frame_available && !row_ready) begin
                    underrun<=1;
                    if(underrun_count!=16'hffff) underrun_count<=underrun_count+1'b1;
                end
            end
        end
    end
endmodule
