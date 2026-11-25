// Original enhanced object-surface engine, experimental command contract v1.
// Exact floor(relative * source_size / destination_size) via remainder stepping;
// no multiplier/divider, destination read, or CPU pixel loop is required.
// One outstanding memory transaction, at least one cycle before its response.
module cb_scaled_blitter (
    input wire clk, reset,
    input wire command_valid,
    output wire command_ready,
    input wire [15:0] command_tag,
    input wire command_fill, command_fill_covered, command_bpp4, command_flip_x, command_flip_y, command_transparent,
    input wire [7:0] command_fill_index,
    input wire [3:0] command_palette, command_band,
    input wire [22:0] command_source, command_destination,
    input wire [8:0] command_source_width, command_source_height,
    input wire [15:0] command_source_stride, command_destination_stride,
    input wire signed [11:0] command_x, command_y,
    input wire [10:0] command_width, command_height,
    input wire [9:0] command_clip_x0, command_clip_y0, command_clip_x1, command_clip_y1,
    output wire completion_valid,
    input wire completion_ready,
    output reg [15:0] completion_tag,
    output reg [2:0] completion_error,
    output wire busy,
    output reg protocol_fault,
    output reg [31:0] command_cycles, sampled_pixels, written_pixels, read_requests, write_requests, memory_stalls,
    output wire memory_valid,
    input wire memory_ready,
    output wire memory_write,
    output wire [22:0] memory_address,
    output wire [31:0] memory_data,
    output wire [3:0] memory_mask,
    input wire memory_response,
    input wire [31:0] memory_read_data
);
    typedef struct packed {
        logic fill, fill_covered, bpp4, flip_x, flip_y, transparent;
        logic [7:0] fill_index;
        logic [3:0] palette, band;
        logic [22:0] source, destination;
        logic [8:0] sw, sh;
        logic [15:0] source_stride, destination_stride;
        logic signed [11:0] x, y;
        logic [10:0] w, h;
        logic [9:0] cx0, cy0, cx1, cy1;
    } descriptor_t;
    descriptor_t q;
    typedef enum logic [4:0] {
        IDLE, VALIDATE, SOURCE_SPAN, DESTINATION_SPAN, CHECK_RANGES,
        SKIP_X_ADD, SKIP_X_CARRY, SKIP_Y_ADD, SKIP_Y_CARRY,
        SAMPLE, READ_REQUEST, READ_WAIT,
        STEP_X_CARRY, STEP_Y_CARRY, WRITE_REQUEST, WRITE_WAIT, FINISH, COMPLETE
    } state_t;
    state_t state;
    reg [9:0] left, right, top, bottom, x, y;
    reg visible;
    reg [10:0] skip_x, skip_y, remainder_x, remainder_y, initial_remainder_x;
    // Source column after flip, stepped directly so that sampling does not
    // recompute it: it counts down from the last column when flipped.
    reg [8:0] mapped_x, initial_mapped_x, source_rows_left;
    reg [7:0] destination_row_index;
    reg [25:0] source_last_row, source_end, destination_last_row, destination_end, destination_row;
    // The byte address of the current sample and of the row's first sample
    // are registers stepped alongside mapped_x, so sampling compares the cache
    // tag against a register instead of the output of an adder.
    reg [22:0] source_address, row_address, destination_address;
    reg cache_valid, write_buffer_valid, finishing_write;
    reg [20:0] cache_tag;
    reg [31:0] cache_data, write_buffer_data;
    reg [22:0] read_address, write_buffer_address;
    reg [3:0] write_buffer_mask;
    reg [15:0] pixel;
    reg [1:0] fill_step;

    function automatic signed [13:0] maximum(input signed [13:0] a, b);
        maximum=a>b ? a:b;
    endfunction
    function automatic signed [13:0] minimum(input signed [13:0] a, b);
        minimum=a<b ? a:b;
    endfunction
    wire signed [13:0] origin_x=$signed({{2{q.x[11]}},q.x});
    wire signed [13:0] origin_y=$signed({{2{q.y[11]}},q.y});
    wire signed [13:0] clipped_left=maximum(maximum(origin_x,14'sd0),$signed({4'b0,q.cx0}));
    wire signed [13:0] clipped_top=maximum(maximum(origin_y,14'sd0),$signed({4'b0,q.cy0}));
    wire signed [13:0] clipped_right=minimum(minimum(origin_x+$signed({3'b0,q.w}),14'sd320),$signed({4'b0,q.cx1}));
    wire signed [13:0] clipped_bottom=minimum(minimum(origin_y+$signed({3'b0,q.h}),14'sd204),$signed({4'b0,q.cy1}));
    wire [9:0] source_row_bytes=q.bpp4 ? ({1'b0,q.sw}+10'd1)>>1:{1'b0,q.sw};
    wire [8:0] stepped_x=q.flip_x ? mapped_x-1'b1:mapped_x+1'b1;
    wire address_step=!q.bpp4 || (q.flip_x ? !mapped_x[0]:mapped_x[0]);
    wire [22:0] stepped_address=q.flip_x ? source_address-{22'b0,address_step}:source_address+{22'b0,address_step};
    wire [22:0] stepped_row=q.flip_y ? row_address-{7'b0,q.source_stride}:row_address+{7'b0,q.source_stride};
    wire [7:0] source_byte=cache_data[source_address[1:0]*8 +: 8];
    wire [3:0] source_nibble=mapped_x[0] ? source_byte[7:4]:source_byte[3:0];
    wire [7:0] source_index=q.bpp4 ? {4'b0,source_nibble}:source_byte;
    wire [7:0] palette_index=q.bpp4 ? {q.palette,source_nibble}:source_byte;
    wire [22:0] destination_word={destination_address[22:2],2'b0};
    wire [3:0] pixel_mask=destination_address[1] ? 4'b1100:4'b0011;
    wire [10:0] next_remainder_x=remainder_x+{2'b0,q.sw};
    wire [10:0] next_remainder_y=remainder_y+{2'b0,q.sh};

    // A fill directly emits one or two whole pixels per aligned word. Partial
    // first/last words use byte masks, including rows starting at the high half.
    // Prepare only before acceptance or after ACK: held requests never change.
    task automatic prepare_fill(input [22:1] address, input [9:0] position);
        reg pair_pixels;
        reg [15:0] value;
        begin
            pair_pixels=!address[1] && position+10'd1<right;
            value=q.fill_covered ? {3'b0,1'b1,q.band,q.fill_index}:16'b0;
            write_buffer_address<={address[22:2],2'b0};
            write_buffer_data<={value,value};
            write_buffer_mask<=address[1] ? 4'b1100:pair_pixels ? 4'b1111:4'b0011;
            fill_step<=pair_pixels ? 2'd2:2'd1;
            state<=WRITE_REQUEST;
        end
    endtask

    // Advance during a store (or transparent sample). At unity/enlargement a
    // single carry suffices; minification keeps the bounded repeated-carry path.
    task automatic advance_sample;
        begin
            if(x==right-1'b1) begin
                if(y==bottom-1'b1) state<=FINISH;
                else begin
                    y<=y+1'b1; x<=left; mapped_x<=initial_mapped_x; remainder_x<=initial_remainder_x;
                    source_address<=row_address;
                    destination_row<=destination_row+{10'b0,q.destination_stride};
                    destination_address<=destination_row[22:0]+{7'b0,q.destination_stride};
                    if({2'b0,q.sh}<=q.h) begin
                        if(next_remainder_y>=q.h) begin
                            remainder_y<=next_remainder_y-q.h;
                            row_address<=stepped_row; source_address<=stepped_row;
                        end else remainder_y<=next_remainder_y;
                        state<=SAMPLE;
                    end else begin remainder_y<=next_remainder_y; state<=STEP_Y_CARRY; end
                end
            end else begin
                x<=x+1'b1; destination_address<=destination_address+23'd2;
                if({2'b0,q.sw}<=q.w) begin
                    if(next_remainder_x>=q.w) begin
                        remainder_x<=next_remainder_x-q.w; mapped_x<=stepped_x; source_address<=stepped_address;
                    end else remainder_x<=next_remainder_x;
                    state<=SAMPLE;
                end else begin remainder_x<=next_remainder_x; state<=STEP_X_CARRY; end
            end
        end
    endtask

    // Write a cached sample into the combiner in the sampling cycle. When an
    // older word must flush first, its pending sample resumes on the ACK edge.
    task automatic buffer_pixel(input [15:0] value, input append_pixel);
        begin
            write_buffer_valid<=1; write_buffer_address<=destination_word;
            if(!append_pixel) begin
                write_buffer_data<=destination_address[1] ? {value,16'b0}:{16'b0,value};
                write_buffer_mask<=pixel_mask;
            end else begin
                if(destination_address[1]) write_buffer_data[31:16]<=value; else write_buffer_data[15:0]<=value;
                write_buffer_mask<=write_buffer_mask|pixel_mask;
            end
            written_pixels<=written_pixels+1'b1; advance_sample();
        end
    endtask
    assign command_ready=!reset && state==IDLE;
    assign completion_valid=!reset && state==COMPLETE;
    assign busy=state!=IDLE;
    assign memory_valid=!reset && (state==READ_REQUEST || state==WRITE_REQUEST);
    assign memory_write=state==WRITE_REQUEST || state==WRITE_WAIT;
    assign memory_address=memory_write ? write_buffer_address:read_address;
    assign memory_data=write_buffer_data;
    assign memory_mask=memory_write ? write_buffer_mask:4'b0;

    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE; q<='0; completion_tag<=0; completion_error<=0; protocol_fault<=0;
            command_cycles<=0; sampled_pixels<=0; written_pixels<=0; read_requests<=0; write_requests<=0; memory_stalls<=0;
            left<=0; right<=0; top<=0; bottom<=0; x<=0; y<=0; visible<=0;
            skip_x<=0; skip_y<=0; remainder_x<=0; remainder_y<=0; initial_remainder_x<=0;
            mapped_x<=0; initial_mapped_x<=0; source_rows_left<=0; destination_row_index<=0;
            source_last_row<=0; source_end<=0; destination_last_row<=0; destination_end<=0; destination_row<=0;
            source_address<=0; row_address<=0; destination_address<=0; cache_valid<=0; cache_tag<=0; cache_data<=0;
            write_buffer_valid<=0; finishing_write<=0; read_address<=0; write_buffer_address<=0;
            write_buffer_data<=0; write_buffer_mask<=0; pixel<=0; fill_step<=0;
        end else begin
            if(state!=IDLE && state!=COMPLETE) command_cycles<=command_cycles+1'b1;
            if((memory_valid && !memory_ready) || ((state==READ_WAIT || state==WRITE_WAIT) && !memory_response))
                memory_stalls<=memory_stalls+1'b1;
            if(memory_response && state!=READ_WAIT && state!=WRITE_WAIT) protocol_fault<=1;
            case(state)
                IDLE: if(command_valid) begin
                    q.fill<=command_fill; q.fill_covered<=command_fill_covered; q.bpp4<=command_bpp4; q.flip_x<=command_flip_x; q.flip_y<=command_flip_y;
                    q.transparent<=command_transparent; q.fill_index<=command_fill_index;
                    q.palette<=command_palette; q.band<=command_band;
                    q.source<=command_source; q.destination<=command_destination;
                    q.sw<=command_source_width; q.sh<=command_source_height;
                    q.source_stride<=command_source_stride; q.destination_stride<=command_destination_stride;
                    q.x<=command_x; q.y<=command_y; q.w<=command_width; q.h<=command_height;
                    q.cx0<=command_clip_x0; q.cy0<=command_clip_y0; q.cx1<=command_clip_x1; q.cy1<=command_clip_y1;
                    completion_tag<=command_tag; completion_error<=0; cache_valid<=0; write_buffer_valid<=0;
                    command_cycles<=1; sampled_pixels<=0; written_pixels<=0; read_requests<=0; write_requests<=0; memory_stalls<=0;
                    mapped_x<=command_flip_x ? command_source_width-1'b1:9'd0; remainder_x<=0; remainder_y<=0;
                    state<=VALIDATE;
                end
                VALIDATE: begin
                    visible<=clipped_left<clipped_right && clipped_top<clipped_bottom;
                    left<=10'(clipped_left); right<=10'(clipped_right); top<=10'(clipped_top); bottom<=10'(clipped_bottom);
                    skip_x<=11'(clipped_left-origin_x); skip_y<=11'(clipped_top-origin_y);
                    if(q.w==0 || q.h==0 || q.w>1024 || q.h>1024 || (!q.fill && (q.sw==0 || q.sh==0 || q.sw>256 || q.sh>256))) begin
                        completion_error<=1; state<=COMPLETE;
                    end else if(q.destination[0] || q.destination_stride[0] || q.destination_stride<640 ||
                                (!q.fill && {6'b0,source_row_bytes}>q.source_stride)) begin
                        completion_error<=2; state<=COMPLETE;
                    end else begin
                        source_last_row<={3'b0,q.source}; source_rows_left<=q.sh-1'b1;
                        destination_last_row<={3'b0,q.destination}; destination_row_index<=0;
                        if(q.fill) begin source_end<=0; state<=DESTINATION_SPAN; end
                        else state<=SOURCE_SPAN;
                    end
                end
                SOURCE_SPAN: begin
                    if(source_rows_left!=0) begin
                        source_last_row<=source_last_row+{10'b0,q.source_stride}; source_rows_left<=source_rows_left-1'b1;
                    end else begin
                        source_end<=source_last_row+{16'b0,source_row_bytes};
                        source_address<=(q.flip_y ? source_last_row[22:0]:q.source)+
                            (q.bpp4 ? {15'b0,mapped_x[8:1]}:{14'b0,mapped_x});
                        state<=DESTINATION_SPAN;
                    end
                end
                DESTINATION_SPAN: begin
                    if({2'b0,destination_row_index}==top)
                        destination_row<=destination_last_row+{15'b0,left,1'b0};
                    if(destination_row_index==203) begin
                        destination_end<=destination_last_row+26'd640; state<=CHECK_RANGES;
                    end else begin
                        destination_row_index<=destination_row_index+1'b1;
                        destination_last_row<=destination_last_row+{10'b0,q.destination_stride};
                    end
                end
                CHECK_RANGES: begin
                    if(destination_end>26'd8388608 || (!q.fill && source_end>26'd8388608)) begin completion_error<=3; state<=COMPLETE; end
                    else if(!q.fill && {3'b0,q.source}<destination_end && {3'b0,q.destination}<source_end) begin completion_error<=4; state<=COMPLETE; end
                    else if(!visible) state<=COMPLETE;
                    else begin
                        x<=left; y<=top; destination_address<=destination_row[22:0];
                        if(q.fill) prepare_fill(destination_row[22:1],left); else state<=SKIP_X_ADD;
                    end
                end
                SKIP_X_ADD: begin
                    if(skip_x==0) begin initial_mapped_x<=mapped_x; row_address<=source_address; initial_remainder_x<=remainder_x; state<=SKIP_Y_ADD; end
                    else begin skip_x<=skip_x-1'b1; remainder_x<=remainder_x+{2'b0,q.sw}; state<=SKIP_X_CARRY; end
                end
                SKIP_X_CARRY: begin
                    if(remainder_x>=q.w) begin remainder_x<=remainder_x-q.w; mapped_x<=stepped_x; source_address<=stepped_address; end
                    else state<=SKIP_X_ADD;
                end
                SKIP_Y_ADD: begin
                    if(skip_y==0) state<=SAMPLE;
                    else begin skip_y<=skip_y-1'b1; remainder_y<=remainder_y+{2'b0,q.sh}; state<=SKIP_Y_CARRY; end
                end
                SKIP_Y_CARRY, STEP_Y_CARRY: begin
                    if(remainder_y>=q.h) begin
                        remainder_y<=remainder_y-q.h;
                        row_address<=stepped_row; source_address<=stepped_row;
                    end else state<=state==SKIP_Y_CARRY ? SKIP_Y_ADD:SAMPLE;
                end
                SAMPLE: begin
                    if(cache_valid && cache_tag==source_address[22:2]) begin
                        sampled_pixels<=sampled_pixels+1'b1;
                        if(q.transparent && source_index==0) advance_sample();
                        else if(write_buffer_valid && write_buffer_address!=destination_word) begin
                            pixel<={3'b0,1'b1,q.band,palette_index}; finishing_write<=0; state<=WRITE_REQUEST;
                        end else buffer_pixel({3'b0,1'b1,q.band,palette_index},write_buffer_valid);
                    end else begin read_address<={source_address[22:2],2'b0}; state<=READ_REQUEST; end
                end
                READ_REQUEST: if(memory_ready) begin read_requests<=read_requests+1'b1; state<=READ_WAIT; end
                READ_WAIT: if(memory_response) begin
                    cache_valid<=1; cache_tag<=read_address[22:2]; cache_data<=memory_read_data; state<=SAMPLE;
                end
                STEP_X_CARRY: begin
                    if(remainder_x>=q.w) begin remainder_x<=remainder_x-q.w; mapped_x<=stepped_x; source_address<=stepped_address; end
                    else state<=SAMPLE;
                end
                WRITE_REQUEST: if(memory_ready) begin
                    write_requests<=write_requests+1'b1; state<=WRITE_WAIT;
                    if(q.fill) begin
                        sampled_pixels<=sampled_pixels+{30'b0,fill_step};
                        written_pixels<=written_pixels+{30'b0,fill_step};
                    end
                end
                WRITE_WAIT: if(memory_response) begin
                    if(q.fill) begin
                        if(x+{8'b0,fill_step}==right) begin
                            if(y==bottom-1'b1) state<=COMPLETE;
                            else begin
                                y<=y+1'b1; x<=left;
                                destination_row<=destination_row+{10'b0,q.destination_stride};
                                prepare_fill(destination_row[22:1]+{7'b0,q.destination_stride[15:1]},left);
                            end
                        end else begin
                            x<=x+{8'b0,fill_step};
                            destination_address<=destination_address+{20'b0,fill_step,1'b0};
                            prepare_fill(destination_address[22:1]+{20'b0,fill_step},x+{8'b0,fill_step});
                        end
                        // Row transitions need the new row's byte address as well.
                        if(x+{8'b0,fill_step}==right && y!=bottom-1'b1)
                            destination_address<=destination_row[22:0]+{7'b0,q.destination_stride};
                    end else if(finishing_write) begin write_buffer_valid<=0; state<=COMPLETE; end
                    else buffer_pixel(pixel,1'b0);
                end
                FINISH: begin
                    if(write_buffer_valid) begin finishing_write<=1; state<=WRITE_REQUEST; end
                    else state<=COMPLETE;
                end
                COMPLETE: if(completion_ready) state<=IDLE;
                default: begin state<=IDLE; protocol_fault<=1; end
            endcase
        end
    end
endmodule
