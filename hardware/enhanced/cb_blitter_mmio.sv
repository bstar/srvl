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
    // Register offsets, bits and descriptor layout come from graphics-abi.json
    // through the generated cb_abi_pkg; firmware uses the same source.
    localparam logic [7:0] REG_ID=cb_abi_pkg::REG_ID;
    localparam logic [7:0] REG_REVISION=cb_abi_pkg::REG_REVISION;
    localparam logic [7:0] REG_STATUS=cb_abi_pkg::REG_STATUS;
    localparam logic [7:0] REG_CONTROL=cb_abi_pkg::REG_CONTROL;
    localparam logic [7:0] REG_IRQ_ENABLE=cb_abi_pkg::REG_IRQ_ENABLE;
    localparam logic [7:0] REG_ERROR=cb_abi_pkg::REG_ERROR;
    localparam logic [7:0] REG_TAG=cb_abi_pkg::REG_TAG;
    localparam logic [7:0] REG_DATA=cb_abi_pkg::REG_DATA;
    localparam logic [7:0] REG_CYCLES=cb_abi_pkg::REG_CYCLES;
    localparam logic [7:0] REG_SAMPLES=cb_abi_pkg::REG_SAMPLES;
    localparam logic [7:0] REG_PIXELS=cb_abi_pkg::REG_PIXELS;
    localparam logic [7:0] REG_READS=cb_abi_pkg::REG_READS;
    localparam logic [7:0] REG_WRITES=cb_abi_pkg::REG_WRITES;
    localparam logic [7:0] REG_STALLS=cb_abi_pkg::REG_STALLS;
    localparam logic [7:0] REG_DESCRIPTOR=cb_abi_pkg::REG_DESCRIPTOR;
    localparam logic [7:0] DEVICE_ID=cb_abi_pkg::DEVICE_ID;
    localparam logic [7:0] REVISION=cb_abi_pkg::REVISION;
    localparam integer DESCRIPTOR_BYTES=cb_abi_pkg::DESCRIPTOR_BYTES;
    localparam integer CONTROL_SUBMIT=cb_abi_pkg::CONTROL_SUBMIT;
    localparam integer CONTROL_ACKNOWLEDGE=cb_abi_pkg::CONTROL_ACKNOWLEDGE;
    localparam integer CONTROL_CLEAR_REJECTION=cb_abi_pkg::CONTROL_CLEAR_REJECTION;
    localparam integer FIELD_FLAGS=cb_abi_pkg::FIELD_FLAGS;
    localparam integer FIELD_FILL_INDEX=cb_abi_pkg::FIELD_FILL_INDEX;
    localparam integer FIELD_COLORS=cb_abi_pkg::FIELD_COLORS;
    localparam integer FIELD_TAG=cb_abi_pkg::FIELD_TAG;
    localparam integer FIELD_SOURCE=cb_abi_pkg::FIELD_SOURCE;
    localparam integer FIELD_DESTINATION=cb_abi_pkg::FIELD_DESTINATION;
    localparam integer FIELD_SOURCE_WIDTH=cb_abi_pkg::FIELD_SOURCE_WIDTH;
    localparam integer FIELD_SOURCE_HEIGHT=cb_abi_pkg::FIELD_SOURCE_HEIGHT;
    localparam integer FIELD_SOURCE_STRIDE=cb_abi_pkg::FIELD_SOURCE_STRIDE;
    localparam integer FIELD_DESTINATION_STRIDE=cb_abi_pkg::FIELD_DESTINATION_STRIDE;
    localparam integer FIELD_X=cb_abi_pkg::FIELD_X;
    localparam integer FIELD_Y=cb_abi_pkg::FIELD_Y;
    localparam integer FIELD_WIDTH=cb_abi_pkg::FIELD_WIDTH;
    localparam integer FIELD_HEIGHT=cb_abi_pkg::FIELD_HEIGHT;
    localparam integer FIELD_CLIP_X0=cb_abi_pkg::FIELD_CLIP_X0;
    localparam integer FIELD_CLIP_Y0=cb_abi_pkg::FIELD_CLIP_Y0;
    localparam integer FIELD_CLIP_X1=cb_abi_pkg::FIELD_CLIP_X1;
    localparam integer FIELD_CLIP_Y1=cb_abi_pkg::FIELD_CLIP_Y1;
    localparam integer FIELD_BYTE_VALUE=cb_abi_pkg::FIELD_BYTE_VALUE;
    localparam logic [1:0] OP_WRITE_BYTE=cb_abi_pkg::OP_WRITE_BYTE;
    localparam logic [2:0] ERROR_FORMAT=cb_abi_pkg::ERROR_FORMAT;
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
    // Graphics-domain launch register: the CPU-domain synchronizer must sample
    // a flop, not the combinational OR of several fault sources.
    reg fault_launch;
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
    wire [7:0] flags=field_byte(FIELD_FLAGS);
    wire [15:0] tag={field_byte(FIELD_TAG+1),field_byte(FIELD_TAG)};
    wire [23:0] source_bytes={field_byte(FIELD_SOURCE+2),field_byte(FIELD_SOURCE+1),field_byte(FIELD_SOURCE)};
    wire [23:0] destination_bytes={field_byte(FIELD_DESTINATION+2),field_byte(FIELD_DESTINATION+1),field_byte(FIELD_DESTINATION)};
    wire [15:0] source_width_bytes={field_byte(FIELD_SOURCE_WIDTH+1),field_byte(FIELD_SOURCE_WIDTH)};
    wire [15:0] source_height_bytes={field_byte(FIELD_SOURCE_HEIGHT+1),field_byte(FIELD_SOURCE_HEIGHT)};
    wire [15:0] x_bytes={field_byte(FIELD_X+1),field_byte(FIELD_X)};
    wire [15:0] y_bytes={field_byte(FIELD_Y+1),field_byte(FIELD_Y)};
    wire [15:0] width_bytes={field_byte(FIELD_WIDTH+1),field_byte(FIELD_WIDTH)};
    wire [15:0] height_bytes={field_byte(FIELD_HEIGHT+1),field_byte(FIELD_HEIGHT)};
    wire [15:0] clip_x0_bytes={field_byte(FIELD_CLIP_X0+1),field_byte(FIELD_CLIP_X0)};
    wire [15:0] clip_y0_bytes={field_byte(FIELD_CLIP_Y0+1),field_byte(FIELD_CLIP_Y0)};
    wire [15:0] clip_x1_bytes={field_byte(FIELD_CLIP_X1+1),field_byte(FIELD_CLIP_X1)};
    wire [15:0] clip_y1_bytes={field_byte(FIELD_CLIP_Y1+1),field_byte(FIELD_CLIP_Y1)};
    wire [7:0] colors=field_byte(FIELD_COLORS);
    wire bad_format=flags[7] || destination_bytes[23] ||
        (flags[1] ? (|flags[7:2]):
         (source_bytes[23] || (|source_width_bytes[15:9]) || (|source_height_bytes[15:9]) ||
          (|x_bytes[15:12]) || (|y_bytes[15:12]) || (|width_bytes[15:11]) || (|height_bytes[15:11]) ||
          (|clip_x0_bytes[15:10]) || (|clip_y0_bytes[15:10]) || (|clip_x1_bytes[15:10]) || (|clip_y1_bytes[15:10])));
    assign byte_valid=!reset && state==BYTE_REQUEST;
    assign byte_write=flags[1:0]==OP_WRITE_BYTE;
    assign byte_address={destination_bytes[22:2],2'b0};
    assign byte_data={24'b0,field_byte(FIELD_BYTE_VALUE)}<<(destination_bytes[1:0]*8);
    assign byte_mask=byte_write ? (4'b0001<<destination_bytes[1:0]):4'b0;
    assign protocol_fault=engine_fault || byte_fault || external_protocol_fault;
    assign irq=!reset && irq_enable && (done || rejected || fault_sync2);
    // The descriptor window starts on a 64-byte boundary (enforced by the
    // generator), so the low six address bits index its bytes.
    wire in_descriptor=bus_address>=REG_DESCRIPTOR && {24'b0,bus_address}<{24'b0,REG_DESCRIPTOR}+DESCRIPTOR_BYTES;
    reg [31:0] counter_read;
    always @* begin
        case({bus_address[7:2],2'b00})
            REG_CYCLES:counter_read=cpu_result.cycles;
            REG_SAMPLES:counter_read=cpu_result.samples;
            REG_PIXELS:counter_read=cpu_result.pixels;
            REG_READS:counter_read=cpu_result.reads;
            REG_WRITES:counter_read=cpu_result.writes;
            REG_STALLS:counter_read=cpu_result.stalls;
            default:counter_read=0;
        endcase
        bus_read_data=0;
        if(in_descriptor) bus_read_data=shadow[bus_address[5:0]];
        else if(bus_address>=REG_CYCLES && bus_address<REG_STALLS+8'd4) bus_read_data=counter_read[bus_address[1:0]*8 +: 8];
        else case(bus_address)
            REG_ID:bus_read_data=DEVICE_ID;
            REG_REVISION:bus_read_data=REVISION;
            REG_STATUS:bus_read_data={irq_enable,init_sync2,fault_sync2,rejected,(done && (|cpu_result.error)),done,cpu_busy,(!cpu_busy && !done)};
            REG_IRQ_ENABLE:bus_read_data={7'b0,irq_enable};
            REG_ERROR:bus_read_data={5'b0,cpu_result.error};
            REG_TAG:bus_read_data=cpu_result.tag[7:0];
            REG_TAG+8'd1:bus_read_data=cpu_result.tag[15:8];
            REG_DATA,REG_DATA+8'd1,REG_DATA+8'd2,REG_DATA+8'd3:bus_read_data=cpu_result.data[bus_address[1:0]*8 +: 8];
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
            fault_sync1<=fault_launch; fault_sync2<=fault_sync1;
            if(bus_write) begin
                if(in_descriptor) shadow[bus_address[5:0]]<=bus_write_data;
                else if(bus_address==REG_IRQ_ENABLE) irq_enable<=bus_write_data[0];
                else if(bus_address==REG_CONTROL) begin
                    if(bus_write_data[CONTROL_CLEAR_REJECTION]) rejected<=0;
                    if(bus_write_data[CONTROL_ACKNOWLEDGE] && done) begin done<=0; acknowledge_toggle<=reply_seen; end
                    if(bus_write_data[CONTROL_SUBMIT]) begin
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
    always @(posedge graphics_clk) fault_launch<=!reset && protocol_fault;
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
                    if(bad_format) begin graphics_result.error<=ERROR_FORMAT; reply_toggle<=!reply_toggle; state<=WAIT_ACK; end
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
        .command_fill_index(field_byte(FIELD_FILL_INDEX)),.command_palette(colors[3:0]),.command_band(colors[7:4]),
        .command_source(source_bytes[22:0]),.command_destination(destination_bytes[22:0]),
        .command_source_width(source_width_bytes[8:0]),.command_source_height(source_height_bytes[8:0]),
        .command_source_stride({field_byte(FIELD_SOURCE_STRIDE+1),field_byte(FIELD_SOURCE_STRIDE)}),.command_destination_stride({field_byte(FIELD_DESTINATION_STRIDE+1),field_byte(FIELD_DESTINATION_STRIDE)}),
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
