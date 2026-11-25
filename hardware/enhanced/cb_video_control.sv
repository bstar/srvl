// CPU-visible native video control: front/back surface ownership, a presented
// frame counter, the RGB444 palette port, tile-plane settings and the tile
// memory port. CPU and graphics clocks are treated as unrelated; single-bit
// toggles/levels cross through two flops and wider values cross only while
// held stable by a pending request.
// Reset: the graphics reset asserts first and the CPU-side reset is released
// later, so every crossing starts from matching zero state.
//
// Frame commit: one CONTROL write may request a surface swap, a latch of the
// staged plane settings, or both. The request is taken only at the scanout's
// PRESENT boundary and both parts apply to the same frame; it is reported back
// as one event that changes FRONT and clears the pending bits together. A
// request written while one is pending is ignored, not queued.
//
// Ownership rule: the front surface belongs to scanout. A graphics write into
// the front surface, or into either surface while a swap is pending, sets a
// sticky ownership fault; it is detection, not prevention.
//
// Tile memory port: TILE_ADDRESS is a word pointer into cb_tile_planes memory.
// Pattern words are four bytes (DATA0..DATA3) and map entries two (DATA0,
// DATA1); writing the last byte of a word stores it and advances the pointer.
// Plane and tile registers are write-only.
module cb_video_control (
    input wire cpu_clk, cpu_reset,
    input wire [7:0] bus_address, bus_write_data,
    input wire bus_write,
    output reg [7:0] bus_read_data,
    // The palette and tile strobes are combinational within the CPU write
    // cycle; the RAMs sample them on their own mid-cycle clock edge.
    output wire palette_write,
    output wire [7:0] palette_index,
    output wire [11:0] palette_rgb,
    output wire tile_write,
    output wire [12:0] tile_address,
    output wire [31:0] tile_data,
    input wire clk, reset,
    input wire present,
    output wire display_valid,
    output reg display_bank,
    output reg [1:0] plane_enable,
    output reg [8:0] plane_x0, plane_x1,
    output reg [7:0] plane_y0, plane_y1,
    input wire surface_write,
    input wire [22:0] surface_write_address,
    input wire underrun,
    output reg ownership_fault
);
    localparam integer BANK=cb_abi_pkg::SURFACE_BANK_BIT;
    localparam [22:0] SURFACE_BASE=cb_abi_pkg::SURFACE_BASE;

    // CPU domain.
    reg enable, request, request_seen, request_swap, request_planes, front, frame_seen;
    reg [7:0] frames, index, low;
    // Staged values are free to change; the held copy is what crosses.
    reg [1:0] staged_enable, held_enable;
    reg [8:0] staged_x0, staged_x1, held_x0, held_x1;
    reg [7:0] staged_y0, staged_y1, held_y0, held_y1;
    reg [12:0] tile_pointer;
    reg [7:0] tile_byte0, tile_byte1, tile_byte2;
    (* ASYNC_REG="TRUE" *) reg ack_meta, ack_sync;
    (* ASYNC_REG="TRUE" *) reg frame_meta, frame_sync;
    (* ASYNC_REG="TRUE" *) reg underrun_meta, underrun_sync;
    (* ASYNC_REG="TRUE" *) reg owner_meta, owner_sync;
    reg taken, frame_toggle;
    wire busy=request!=request_seen;
    wire tile_map=tile_pointer[12];
    wire want_swap=bus_write_data[cb_abi_pkg::VIDEO_CONTROL_SWAP];
    wire want_planes=bus_write_data[cb_abi_pkg::VIDEO_CONTROL_LATCH_PLANES];
    assign palette_write=bus_write && !cpu_reset && bus_address==cb_abi_pkg::VIDEO_REG_PALETTE_HIGH;
    assign palette_index=index;
    assign palette_rgb={bus_write_data[3:0],low};
    assign tile_write=bus_write && !cpu_reset &&
        bus_address==(tile_map ? cb_abi_pkg::VIDEO_REG_TILE_DATA1:cb_abi_pkg::VIDEO_REG_TILE_DATA3);
    assign tile_address=tile_pointer;
    assign tile_data=tile_map ? {16'b0,bus_write_data,tile_byte0}:{bus_write_data,tile_byte2,tile_byte1,tile_byte0};
    always @* begin
        bus_read_data=0;
        case(bus_address)
            cb_abi_pkg::VIDEO_REG_STATUS: begin
                bus_read_data[cb_abi_pkg::VIDEO_STATUS_SWAP_PENDING]=busy && request_swap;
                bus_read_data[cb_abi_pkg::VIDEO_STATUS_ENABLED]=enable;
                bus_read_data[cb_abi_pkg::VIDEO_STATUS_FRONT]=front;
                bus_read_data[cb_abi_pkg::VIDEO_STATUS_PLANES_PENDING]=busy && request_planes;
                bus_read_data[cb_abi_pkg::VIDEO_STATUS_UNDERRUN]=underrun_sync;
                bus_read_data[cb_abi_pkg::VIDEO_STATUS_OWNERSHIP_FAULT]=owner_sync;
            end
            cb_abi_pkg::VIDEO_REG_CONTROL: bus_read_data[cb_abi_pkg::VIDEO_CONTROL_ENABLE]=enable;
            cb_abi_pkg::VIDEO_REG_FRAME: bus_read_data=frames;
            cb_abi_pkg::VIDEO_REG_PALETTE_INDEX: bus_read_data=index;
            default: bus_read_data=0;
        endcase
    end
    always @(posedge cpu_clk) begin
        if(cpu_reset) begin
            enable<=0; request<=0; request_seen<=0; request_swap<=0; request_planes<=0; front<=0; frame_seen<=0;
            frames<=0; index<=0; low<=0;
            staged_enable<=0; staged_x0<=0; staged_x1<=0; staged_y0<=0; staged_y1<=0;
            held_enable<=0; held_x0<=0; held_x1<=0; held_y0<=0; held_y1<=0;
            tile_pointer<=0; tile_byte0<=0; tile_byte1<=0; tile_byte2<=0;
            ack_meta<=0; ack_sync<=0; frame_meta<=0; frame_sync<=0;
            underrun_meta<=0; underrun_sync<=0; owner_meta<=0; owner_sync<=0;
        end else begin
            ack_meta<=taken; ack_sync<=ack_meta;
            frame_meta<=frame_toggle; frame_sync<=frame_meta;
            underrun_meta<=underrun; underrun_sync<=underrun_meta;
            owner_meta<=ownership_fault; owner_sync<=owner_meta;
            if(ack_sync!=request_seen) begin
                request_seen<=ack_sync;
                if(request_swap) front<=!front;
            end
            if(frame_sync!=frame_seen) begin frame_seen<=frame_sync; frames<=frames+1'b1; end
            if(bus_write) case(bus_address)
                cb_abi_pkg::VIDEO_REG_CONTROL: begin
                    enable<=bus_write_data[cb_abi_pkg::VIDEO_CONTROL_ENABLE];
                    if((want_swap || want_planes) && !busy) begin
                        request<=!request; request_swap<=want_swap; request_planes<=want_planes;
                        if(want_planes) begin
                            held_enable<=staged_enable; held_x0<=staged_x0; held_x1<=staged_x1;
                            held_y0<=staged_y0; held_y1<=staged_y1;
                        end
                    end
                end
                cb_abi_pkg::VIDEO_REG_PALETTE_INDEX: index<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_PALETTE_LOW: low<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_PALETTE_HIGH: index<=index+1'b1;
                cb_abi_pkg::VIDEO_REG_PLANE_ENABLE: staged_enable<=bus_write_data[1:0];
                cb_abi_pkg::VIDEO_REG_PLANE0_X_LOW: staged_x0[7:0]<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_PLANE0_X_HIGH: staged_x0[8]<=bus_write_data[0];
                cb_abi_pkg::VIDEO_REG_PLANE0_Y: staged_y0<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_PLANE1_X_LOW: staged_x1[7:0]<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_PLANE1_X_HIGH: staged_x1[8]<=bus_write_data[0];
                cb_abi_pkg::VIDEO_REG_PLANE1_Y: staged_y1<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_TILE_ADDRESS_LOW: tile_pointer[7:0]<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_TILE_ADDRESS_HIGH: tile_pointer[12:8]<=bus_write_data[4:0];
                cb_abi_pkg::VIDEO_REG_TILE_DATA0: tile_byte0<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_TILE_DATA1: if(tile_map) tile_pointer<=tile_pointer+1'b1; else tile_byte1<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_TILE_DATA2: tile_byte2<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_TILE_DATA3: if(!tile_map) tile_pointer<=tile_pointer+1'b1;
                default: ;
            endcase
        end
    end

    // Graphics domain. request_swap, request_planes and the held plane values
    // changed no later than the request toggle and stay put until it is taken.
    (* ASYNC_REG="TRUE" *) reg request_meta, request_sync;
    (* ASYNC_REG="TRUE" *) reg enable_meta, enable_sync;
    wire pending=request_sync!=taken;
    wire swap_pending=pending && request_swap;
    wire in_surfaces=(surface_write_address[22:BANK+1]==SURFACE_BASE[22:BANK+1]);
    wire _unused_address=^surface_write_address[BANK-1:0];
    assign display_valid=enable_sync;
    always @(posedge clk) begin
        if(reset) begin
            request_meta<=0; request_sync<=0; enable_meta<=0; enable_sync<=0;
            taken<=0; frame_toggle<=0; display_bank<=0; ownership_fault<=0;
            plane_enable<=0; plane_x0<=0; plane_x1<=0; plane_y0<=0; plane_y1<=0;
        end else begin
            request_meta<=request; request_sync<=request_meta;
            enable_meta<=enable; enable_sync<=enable_meta;
            if(present) begin
                frame_toggle<=!frame_toggle;
                if(pending) begin
                    taken<=request_sync;
                    if(request_swap) display_bank<=!display_bank;
                    if(request_planes) begin
                        plane_enable<=held_enable; plane_x0<=held_x0; plane_x1<=held_x1;
                        plane_y0<=held_y0; plane_y1<=held_y1;
                    end
                end
            end
            if(surface_write && enable_sync && in_surfaces &&
               (surface_write_address[BANK]==display_bank || swap_pending)) ownership_fault<=1;
        end
    end
endmodule
