// Original experimental enhanced MMIO v1. CPU-local, nonblocking registers;
// bundled-data toggle mailboxes cross whole commands and held results.
// Both clocks must run while the common reset is asserted. No CPU RDY adapter,
// frame ownership or stable public SDK is implied by this component.
module cb_blitter_mmio (
    input wire cpu_clk, graphics_clk, reset,
    input wire [7:0] bus_address, bus_write_data,
    input wire bus_write,
    output reg [7:0] bus_read_data,
    output wire irq,
    input wire initialized, external_protocol_fault,
    output wire protocol_fault,
    output wire memory_valid, memory_write,
    input wire memory_ready, memory_response,
    output wire [22:0] memory_address,
    output wire [31:0] memory_data,
    output wire [3:0] memory_mask,
    input wire [31:0] memory_read_data,
    output wire byte_valid, byte_write,
    input wire byte_ready, byte_response,
    output wire [22:0] byte_address,
    output wire [31:0] byte_data,
    output wire [3:0] byte_mask,
    input wire [31:0] byte_read_data
);
    localparam integer DESCRIPTOR_BYTES=36;
    typedef struct packed {
        logic [15:0] tag;
        logic [2:0] error;
        logic [31:0] data, cycles, samples, pixels, reads, writes, stalls;
    } result_t;
    reg [7:0] shadow [0:DESCRIPTOR_BYTES-1];
    reg [DESCRIPTOR_BYTES*8-1:0] submitted, active;
    result_t graphics_result, cpu_result;
    reg request_toggle, request_sync1, request_sync2, request_seen;
    reg reply_toggle, reply_sync1, reply_sync2, reply_seen;
    reg acknowledge_toggle, acknowledge_sync1, acknowledge_sync2;
    reg cpu_busy, done, rejected, irq_enable;
    reg init_sync1, init_sync2, fault_sync1, fault_sync2;
    reg byte_fault;
    typedef enum logic [2:0] {IDLE,DECODE,DRAW_REQUEST,DRAW_WAIT,BYTE_REQUEST,BYTE_WAIT,WAIT_ACK} state_t;
    state_t state;
    reg [31:0] elapsed, byte_stalls;
    wire engine_ready, engine_done, engine_fault, _unused_engine_busy;
    wire [15:0] engine_tag;
    wire [2:0] engine_error;
    wire [31:0] engine_cycles, engine_samples, engine_pixels, engine_reads, engine_writes, engine_stalls;
    function automatic [7:0] field_byte(input integer index);
        field_byte=active[index*8 +: 8];
    endfunction
    wire [7:0] flags=field_byte(0);
    wire [15:0] tag={field_byte(4),field_byte(3)};
    wire [23:0] source_bytes={field_byte(7),field_byte(6),field_byte(5)};
    wire [23:0] destination_bytes={field_byte(10),field_byte(9),field_byte(8)};
    wire [15:0] source_width_bytes={field_byte(12),field_byte(11)};
    wire [15:0] source_height_bytes={field_byte(14),field_byte(13)};
    wire [15:0] x_bytes={field_byte(20),field_byte(19)};
    wire [15:0] y_bytes={field_byte(22),field_byte(21)};
    wire [15:0] width_bytes={field_byte(24),field_byte(23)};
    wire [15:0] height_bytes={field_byte(26),field_byte(25)};
    wire [15:0] clip_x0_bytes={field_byte(28),field_byte(27)};
    wire [15:0] clip_y0_bytes={field_byte(30),field_byte(29)};
    wire [15:0] clip_x1_bytes={field_byte(32),field_byte(31)};
    wire [15:0] clip_y1_bytes={field_byte(34),field_byte(33)};
    wire [7:0] colors=field_byte(2);
    wire bad_format=flags[7] || destination_bytes[23] ||
        (flags[1] ? (|flags[7:2]):
         (source_bytes[23] || (|source_width_bytes[15:9]) || (|source_height_bytes[15:9]) ||
          (|x_bytes[15:12]) || (|y_bytes[15:12]) || (|width_bytes[15:11]) || (|height_bytes[15:11]) ||
          (|clip_x0_bytes[15:10]) || (|clip_y0_bytes[15:10]) || (|clip_x1_bytes[15:10]) || (|clip_y1_bytes[15:10])));
    assign byte_valid=!reset && state==BYTE_REQUEST;
    assign byte_write=flags[1:0]==2;
    assign byte_address={destination_bytes[22:2],2'b0};
    assign byte_data={24'b0,field_byte(35)}<<(destination_bytes[1:0]*8);
    assign byte_mask=byte_write ? (4'b0001<<destination_bytes[1:0]):4'b0;
    assign protocol_fault=engine_fault || byte_fault || external_protocol_fault;
    assign irq=!reset && irq_enable && (done || rejected || fault_sync2);
    reg [31:0] counter_read;
    always @* begin
        case(bus_address[7:2])
            6'h03:counter_read=cpu_result.cycles;
            6'h04:counter_read=cpu_result.samples;
            6'h05:counter_read=cpu_result.pixels;
            6'h06:counter_read=cpu_result.reads;
            6'h07:counter_read=cpu_result.writes;
            6'h08:counter_read=cpu_result.stalls;
            default:counter_read=0;
        endcase
        bus_read_data=0;
        if(bus_address>=8'h40 && bus_address<8'h64) bus_read_data=shadow[bus_address[5:0]];
        else if(bus_address>=8'h0c && bus_address<8'h24) bus_read_data=counter_read[bus_address[1:0]*8 +: 8];
        else case(bus_address)
            8'h00:bus_read_data=8'hcb;
            8'h01:bus_read_data=1;
            8'h02:bus_read_data={irq_enable,init_sync2,fault_sync2,rejected,(done && (|cpu_result.error)),done,cpu_busy,(!cpu_busy && !done)};
            8'h04:bus_read_data={7'b0,irq_enable};
            8'h05:bus_read_data={5'b0,cpu_result.error};
            8'h06:bus_read_data=cpu_result.tag[7:0];
            8'h07:bus_read_data=cpu_result.tag[15:8];
            8'h08,8'h09,8'h0a,8'h0b:bus_read_data=cpu_result.data[bus_address[1:0]*8 +: 8];
            default:bus_read_data=0;
        endcase
    end
    always @(posedge cpu_clk) begin
        if(reset) begin
            for(integer i=0;i<DESCRIPTOR_BYTES;i=i+1) shadow[i]<=0;
            submitted<=0; request_toggle<=0; acknowledge_toggle<=0;
            reply_sync1<=0; reply_sync2<=0; reply_seen<=0;
            cpu_result<='0; cpu_busy<=0; done<=0; rejected<=0; irq_enable<=0;
            init_sync1<=0; init_sync2<=0; fault_sync1<=0; fault_sync2<=0;
        end else begin
            reply_sync1<=reply_toggle; reply_sync2<=reply_sync1;
            init_sync1<=initialized; init_sync2<=init_sync1;
            fault_sync1<=protocol_fault; fault_sync2<=fault_sync1;
            if(bus_write) begin
                if(bus_address>=8'h40 && bus_address<8'h64) shadow[bus_address[5:0]]<=bus_write_data;
                else if(bus_address==8'h04) irq_enable<=bus_write_data[0];
                else if(bus_address==8'h03) begin
                    if(bus_write_data[2]) rejected<=0;
                    if(bus_write_data[1] && done) begin done<=0; acknowledge_toggle<=reply_seen; end
                    if(bus_write_data[0]) begin
                        // ACK+GO does not recycle a held completion in one write.
                        // A rejected GO cannot replace submitted data or its tag.
                        if(!cpu_busy && !done) begin
                            for(integer i=0;i<DESCRIPTOR_BYTES;i=i+1) submitted[i*8 +: 8]<=shadow[i];
                            request_toggle<=!request_toggle; cpu_busy<=1;
                        end else rejected<=1;
                    end
                end
            end
            // A new completion wins over a simultaneous control write.
            if(reply_sync2!=reply_seen) begin
                reply_seen<=reply_sync2; cpu_result<=graphics_result; cpu_busy<=0; done<=1;
            end
        end
    end
    always @(posedge graphics_clk) begin
        if(reset) begin
            request_sync1<=0; request_sync2<=0; request_seen<=0;
            acknowledge_sync1<=0; acknowledge_sync2<=0; reply_toggle<=0;
            active<=0; graphics_result<='0; state<=IDLE; elapsed<=0; byte_stalls<=0; byte_fault<=0;
        end else begin
            request_sync1<=request_toggle; request_sync2<=request_sync1;
            acknowledge_sync1<=acknowledge_toggle; acknowledge_sync2<=acknowledge_sync1;
            if(state!=IDLE && state!=WAIT_ACK) elapsed<=elapsed+1'b1;
            if((byte_valid && !byte_ready) || (state==BYTE_WAIT && !byte_response)) byte_stalls<=byte_stalls+1'b1;
            if(byte_response && state!=BYTE_WAIT) byte_fault<=1;
            case(state)
                IDLE: if(request_sync2!=request_seen) begin
                    request_seen<=request_sync2; active<=submitted; elapsed<=0; byte_stalls<=0; state<=DECODE;
                end
                DECODE: begin
                    graphics_result<='0; graphics_result.tag<=tag;
                    if(bad_format) begin graphics_result.error<=5; reply_toggle<=!reply_toggle; state<=WAIT_ACK; end
                    else state<=flags[1] ? BYTE_REQUEST:DRAW_REQUEST;
                end
                DRAW_REQUEST: if(engine_ready) state<=DRAW_WAIT;
                DRAW_WAIT: if(engine_done) begin
                    graphics_result.tag<=engine_tag; graphics_result.error<=engine_error;
                    graphics_result.data<=0; graphics_result.cycles<=engine_cycles;
                    graphics_result.samples<=engine_samples; graphics_result.pixels<=engine_pixels;
                    graphics_result.reads<=engine_reads; graphics_result.writes<=engine_writes; graphics_result.stalls<=engine_stalls;
                    reply_toggle<=!reply_toggle; state<=WAIT_ACK;
                end
                BYTE_REQUEST: if(byte_ready) state<=BYTE_WAIT;
                BYTE_WAIT: if(byte_response) begin
                    graphics_result.data<=byte_write ? 32'b0:{24'b0,byte_read_data[destination_bytes[1:0]*8 +: 8]};
                    graphics_result.cycles<=elapsed+1'b1; graphics_result.stalls<=byte_stalls;
                    graphics_result.reads<=byte_write ? 32'd0:32'd1;
                    graphics_result.writes<=byte_write ? 32'd1:32'd0;
                    reply_toggle<=!reply_toggle; state<=WAIT_ACK;
                end
                WAIT_ACK: if(acknowledge_sync2==reply_toggle) state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
    cb_scaled_blitter engine (
        .clk(graphics_clk),.reset(reset),.command_valid(state==DRAW_REQUEST && !reset),.command_ready(engine_ready),
        .command_tag(tag),.command_fill(flags[0]),.command_fill_covered(flags[2]),.command_bpp4(flags[3]),
        .command_flip_x(flags[4]),.command_flip_y(flags[5]),.command_transparent(flags[6]),
        .command_fill_index(field_byte(1)),.command_palette(colors[3:0]),.command_band(colors[7:4]),
        .command_source(source_bytes[22:0]),.command_destination(destination_bytes[22:0]),
        .command_source_width(source_width_bytes[8:0]),.command_source_height(source_height_bytes[8:0]),
        .command_source_stride({field_byte(16),field_byte(15)}),.command_destination_stride({field_byte(18),field_byte(17)}),
        .command_x(x_bytes[11:0]),.command_y(y_bytes[11:0]),.command_width(width_bytes[10:0]),.command_height(height_bytes[10:0]),
        .command_clip_x0(clip_x0_bytes[9:0]),.command_clip_y0(clip_y0_bytes[9:0]),
        .command_clip_x1(clip_x1_bytes[9:0]),.command_clip_y1(clip_y1_bytes[9:0]),
        .completion_valid(engine_done),.completion_ready(state==DRAW_WAIT),.completion_tag(engine_tag),.completion_error(engine_error),
        .busy(_unused_engine_busy),.protocol_fault(engine_fault),.command_cycles(engine_cycles),.sampled_pixels(engine_samples),.written_pixels(engine_pixels),
        .read_requests(engine_reads),.write_requests(engine_writes),.memory_stalls(engine_stalls),
        .memory_valid(memory_valid),.memory_ready(memory_ready),.memory_write(memory_write),.memory_address(memory_address),
        .memory_data(memory_data),.memory_mask(memory_mask),.memory_response(memory_response),.memory_read_data(memory_read_data)
    );
endmodule
