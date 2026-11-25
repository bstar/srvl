// CPU-visible native video control: front/back surface ownership, a presented
// frame counter and the RGB444 palette port. CPU and graphics clocks are
// treated as unrelated; single-bit toggles/levels cross through two flops.
// Reset: the graphics reset asserts first and the CPU-side reset is released
// later, so every crossing starts from matching zero state.
//
// Ownership rule: the front surface belongs to scanout. A swap is requested by
// the CPU, taken only at the scanout's PRESENT boundary, and reported back as
// one event that changes FRONT and clears SWAP_PENDING together. A graphics
// write into the front surface, or into either surface while a swap is
// pending, sets a sticky ownership fault; it is detection, not prevention.
module cb_video_control (
    input wire cpu_clk, cpu_reset,
    input wire [7:0] bus_address, bus_write_data,
    input wire bus_write,
    output reg [7:0] bus_read_data,
    // The palette strobe is combinational within the CPU write cycle; the
    // palette RAM samples it on its own mid-cycle clock edge.
    output wire palette_write,
    output wire [7:0] palette_index,
    output wire [11:0] palette_rgb,
    input wire clk, reset,
    input wire present,
    output wire display_valid,
    output reg display_bank,
    input wire surface_write,
    input wire [22:0] surface_write_address,
    input wire underrun,
    output reg ownership_fault
);
    localparam integer BANK=cb_abi_pkg::SURFACE_BANK_BIT;
    localparam [22:0] SURFACE_BASE=cb_abi_pkg::SURFACE_BASE;

    // CPU domain.
    reg enable, swap_request, swap_seen, front, frame_seen;
    reg [7:0] frames, index, low;
    (* ASYNC_REG="TRUE" *) reg ack_meta, ack_sync;
    (* ASYNC_REG="TRUE" *) reg frame_meta, frame_sync;
    (* ASYNC_REG="TRUE" *) reg underrun_meta, underrun_sync;
    (* ASYNC_REG="TRUE" *) reg owner_meta, owner_sync;
    reg swap_taken, frame_toggle;
    wire swap_busy=swap_request!=swap_seen;
    assign palette_write=bus_write && !cpu_reset && bus_address==cb_abi_pkg::VIDEO_REG_PALETTE_HIGH;
    assign palette_index=index;
    assign palette_rgb={bus_write_data[3:0],low};
    always @* begin
        bus_read_data=0;
        case(bus_address)
            cb_abi_pkg::VIDEO_REG_STATUS: begin
                bus_read_data[cb_abi_pkg::VIDEO_STATUS_SWAP_PENDING]=swap_busy;
                bus_read_data[cb_abi_pkg::VIDEO_STATUS_ENABLED]=enable;
                bus_read_data[cb_abi_pkg::VIDEO_STATUS_FRONT]=front;
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
            enable<=0; swap_request<=0; swap_seen<=0; front<=0; frame_seen<=0;
            frames<=0; index<=0; low<=0;
            ack_meta<=0; ack_sync<=0; frame_meta<=0; frame_sync<=0;
            underrun_meta<=0; underrun_sync<=0; owner_meta<=0; owner_sync<=0;
        end else begin
            ack_meta<=swap_taken; ack_sync<=ack_meta;
            frame_meta<=frame_toggle; frame_sync<=frame_meta;
            underrun_meta<=underrun; underrun_sync<=underrun_meta;
            owner_meta<=ownership_fault; owner_sync<=owner_meta;
            if(ack_sync!=swap_seen) begin swap_seen<=ack_sync; front<=!front; end
            if(frame_sync!=frame_seen) begin frame_seen<=frame_sync; frames<=frames+1'b1; end
            if(bus_write) case(bus_address)
                cb_abi_pkg::VIDEO_REG_CONTROL: begin
                    enable<=bus_write_data[cb_abi_pkg::VIDEO_CONTROL_ENABLE];
                    // A request while one is pending is ignored, not queued.
                    if(bus_write_data[cb_abi_pkg::VIDEO_CONTROL_SWAP] && !swap_busy) swap_request<=!swap_request;
                end
                cb_abi_pkg::VIDEO_REG_PALETTE_INDEX: index<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_PALETTE_LOW: low<=bus_write_data;
                cb_abi_pkg::VIDEO_REG_PALETTE_HIGH: index<=index+1'b1;
                default: ;
            endcase
        end
    end

    // Graphics domain.
    (* ASYNC_REG="TRUE" *) reg request_meta, request_sync;
    (* ASYNC_REG="TRUE" *) reg enable_meta, enable_sync;
    wire swap_pending=request_sync!=swap_taken;
    wire in_surfaces=(surface_write_address[22:BANK+1]==SURFACE_BASE[22:BANK+1]);
    wire _unused_address=^surface_write_address[BANK-1:0];
    assign display_valid=enable_sync;
    always @(posedge clk) begin
        if(reset) begin
            request_meta<=0; request_sync<=0; enable_meta<=0; enable_sync<=0;
            swap_taken<=0; frame_toggle<=0; display_bank<=0; ownership_fault<=0;
        end else begin
            request_meta<=swap_request; request_sync<=request_meta;
            enable_meta<=enable; enable_sync<=enable_meta;
            if(present) begin
                frame_toggle<=!frame_toggle;
                if(swap_pending) begin display_bank<=!display_bank; swap_taken<=request_sync; end
            end
            if(surface_write && enable_sync && in_surfaces &&
               (surface_write_address[BANK]==display_bank || swap_pending)) ownership_fault<=1;
        end
    end
endmodule
