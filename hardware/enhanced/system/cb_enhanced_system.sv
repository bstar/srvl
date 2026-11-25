// Enhanced console skeleton: R65C02, block-RAM work RAM and ROM, the graphics
// MMIO/blitter, native video control, two block-RAM tile planes and scanout.
// The blitter, CPU byte port and scanout share one SDRAM service.
// No audio, input or loader yet.
//
// Clocks: clk is the 64 MHz graphics/SDRAM clock, memory_clk a real slower
// clock (not a gated one) and video_clk the 25.2 MHz pixel clock. The three
// are treated as unrelated. Block RAM only has rising-edge clocks, so RAM, ROM
// and the palette use the rising edge of memory_clk while the CPU and its
// registers use the falling edge of that same net: memory sees a settled
// address mid-cycle and the CPU sees registered data half a cycle later, with
// no logic-derived clock anywhere.
// reset and video_reset must assert together; the CPU reset is derived here
// and released a few CPU edges after the graphics reset.
module cb_enhanced_system #(
    parameter ROM_FILE="enhanced-demo.hex",
    parameter integer SDRAM_INIT_CYCLES=12800
) (
    // reset is synchronous to clk and also asserts the CPU-domain synchronizer.
    /* verilator lint_off SYNCASYNCNET */
    input wire clk, reset, memory_clk,
    /* verilator lint_on SYNCASYNCNET */
    input wire video_clk, video_reset,
    output wire [11:0] video_rgb,
    output wire video_de, video_hsync, video_vsync,
    output wire [9:0] video_x, video_y,
    output wire video_frame_valid,
    output wire [7:0] diagnostic,
    output wire initialized, protocol_fault, ownership_fault, underrun, display_bank,
    output wire [10:0] sdram_a,
    output wire [1:0] sdram_ba,
    output wire [3:0] sdram_dqm,
    output wire sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n,
    input wire [31:0] dq_in,
    output wire [31:0] dq_out,
    output wire dq_oe
);
    localparam [15:0] DIAGNOSTIC=16'h403f;
    wire cpu_clk=!memory_clk;
    wire cpu_reset;
    cb_reset_sync cpu_reset_sync (.clk(cpu_clk),.async_reset(reset),.reset(cpu_reset));

    wire [15:0] address;
    wire [7:0] write_data, graphics_data, video_data;
    wire write_enable, irq;
    wire _unused_write_n, _unused_read_enable, _unused_sync;
    reg [7:0] read_data;
    core cpu (.clk_clk_i(cpu_clk),.rst_rst_n_i(!cpu_reset),.d_i(read_data),.a_o(address),.d_o(write_data),
        .wr_o(write_enable),.wr_n_o(_unused_write_n),.rd_o(_unused_read_enable),.sync_o(_unused_sync),
        .rdy_i(1'b1),.irq_n_i(!irq),.nmi_n_i(1'b1),.so_n_i(1'b1));

    (* ram_style="block" *) reg [7:0] ram [0:8191];
    (* ram_style="block" *) reg [7:0] rom [0:32767];
    initial $readmemh(ROM_FILE,rom);
    reg [7:0] ram_data, rom_data, result;
    wire bus_write=write_enable && !cpu_reset;
    wire select_ram=address[15:13]==3'b000;
    wire select_graphics=address[15:8]==cb_abi_pkg::BASE_PAGE;
    wire select_video=address[15:8]==cb_abi_pkg::VIDEO_PAGE;
    always @(posedge memory_clk) begin
        if(bus_write && select_ram) ram[address[12:0]]<=write_data;
        ram_data<=ram[address[12:0]];
        rom_data<=rom[address[14:0]];
    end
    always @(posedge cpu_clk) begin
        if(cpu_reset) result<=0;
        else if(bus_write && address==DIAGNOSTIC) result<=write_data;
    end
    always @* begin
        if(address[15]) read_data=rom_data;
        else if(select_ram) read_data=ram_data;
        else if(select_graphics) read_data=graphics_data;
        else if(select_video) read_data=video_data;
        else read_data=0;
    end
    assign diagnostic=result;

    wire memory_valid, memory_ready, memory_write, memory_response;
    wire [22:0] memory_address;
    wire [31:0] memory_data;
    wire [3:0] memory_mask;
    wire byte_valid, byte_ready, byte_write, byte_response;
    wire [22:0] byte_address;
    wire [31:0] byte_data;
    wire [3:0] byte_mask;
    wire scan_valid, scan_ready, scan_response, scan_fault, arbiter_fault;
    wire [22:0] scan_address;
    wire [31:0] shared_read_data;
    cb_blitter_mmio registers (.cpu_clk(cpu_clk),.graphics_clk(clk),.reset(reset),
        .bus_address(address[7:0]),.bus_write_data(write_data),.bus_write(bus_write && select_graphics),
        .bus_read_data(graphics_data),.irq(irq),.initialized(initialized),
        .external_protocol_fault(arbiter_fault || scan_fault),.protocol_fault(protocol_fault),
        .memory_valid(memory_valid),.memory_ready(memory_ready),.memory_write(memory_write),.memory_address(memory_address),
        .memory_data(memory_data),.memory_mask(memory_mask),.memory_response(memory_response),.memory_read_data(shared_read_data),
        .byte_valid(byte_valid),.byte_ready(byte_ready),.byte_write(byte_write),.byte_address(byte_address),
        .byte_data(byte_data),.byte_mask(byte_mask),.byte_response(byte_response),.byte_read_data(shared_read_data));

    // An accepted graphics write is checked against surface ownership.
    wire engine_write=memory_valid && memory_ready && memory_write;
    wire upload_write=byte_valid && byte_ready && byte_write;
    wire present, display_valid, palette_write;
    wire [7:0] palette_index;
    wire [11:0] palette_rgb;
    wire [15:0] _unused_underruns;
    wire tile_write, tile_start, tile_valid, tile_take;
    wire [12:0] tile_address;
    wire [31:0] tile_data;
    wire [1:0] plane_enable;
    wire [8:0] plane_x0, plane_x1, tile_back, tile_front;
    wire [7:0] plane_y0, plane_y1, tile_line;
    cb_tile_planes planes (.write_clk(memory_clk),.write_enable(tile_write),.write_address(tile_address),.write_data(tile_data),
        .clk(clk),.reset(reset),.enable(plane_enable),.scroll_x0(plane_x0),.scroll_x1(plane_x1),
        .scroll_y0(plane_y0),.scroll_y1(plane_y1),.start(tile_start),.line(tile_line),
        .valid(tile_valid),.take(tile_take),.back(tile_back),.front(tile_front));
    cb_video_control video_control (.cpu_clk(cpu_clk),.cpu_reset(cpu_reset),
        .tile_write(tile_write),.tile_address(tile_address),.tile_data(tile_data),
        .plane_enable(plane_enable),.plane_x0(plane_x0),.plane_x1(plane_x1),.plane_y0(plane_y0),.plane_y1(plane_y1),
        .bus_address(address[7:0]),.bus_write_data(write_data),.bus_write(bus_write && select_video),
        .bus_read_data(video_data),.palette_write(palette_write),.palette_index(palette_index),.palette_rgb(palette_rgb),
        .clk(clk),.reset(reset),.present(present),.display_valid(display_valid),.display_bank(display_bank),
        .surface_write(engine_write || upload_write),
        .surface_write_address(engine_write ? memory_address:byte_address),
        .underrun(underrun),.ownership_fault(ownership_fault));
    cb_native_scanout #(.SURFACE_BASE(cb_abi_pkg::SURFACE_BASE)) scanout (.clk(clk),.reset(reset),
        .video_clk(video_clk),.video_reset(video_reset),
        .display_valid(display_valid),.display_bank(display_bank),.present(present),
        .read_valid(scan_valid),.read_ready(scan_ready),.read_response(scan_response),
        .read_address(scan_address),.read_data(shared_read_data),
        .tile_start(tile_start),.tile_line(tile_line),.tile_valid(tile_valid),.tile_take(tile_take),
        .tile_back(tile_back),.tile_front(tile_front),
        .palette_clk(memory_clk),.palette_write(palette_write),.palette_index(palette_index),.palette_rgb(palette_rgb),
        .video_rgb(video_rgb),.video_de(video_de),.video_hsync(video_hsync),.video_vsync(video_vsync),
        .video_x(video_x),.video_y(video_y),.video_frame_valid(video_frame_valid),
        .underrun(underrun),.underrun_count(_unused_underruns),.protocol_fault(scan_fault));

    wire controller_valid, controller_ready, controller_write, controller_response;
    wire [22:0] controller_address;
    wire [31:0] controller_data, controller_read_data;
    wire [3:0] controller_mask;
    wire [2:0] ready, response;
    assign {scan_ready,memory_ready,byte_ready}=ready;
    assign {scan_response,memory_response,byte_response}=response;
    cb_graphics_arbiter arbiter (.clk(clk),.reset(reset),
        .client_valid({scan_valid,memory_valid,byte_valid}),.client_ready(ready),
        .client_write({1'b0,memory_write,byte_write}),.client_address({scan_address,memory_address,byte_address}),
        .client_data({32'b0,memory_data,byte_data}),.client_mask({4'b0,memory_mask,byte_mask}),
        .client_response(response),.client_read_data(shared_read_data),.protocol_fault(arbiter_fault),
        .memory_valid(controller_valid),.memory_ready(controller_ready),
        .memory_write(controller_write),.memory_address(controller_address),.memory_data(controller_data),.memory_mask(controller_mask),
        .memory_response(controller_response),.memory_read_data(controller_read_data));
    cb_graphics_sdram #(.INIT_CYCLES(SDRAM_INIT_CYCLES)) memory (.clk(clk),.reset(reset),
        .request(controller_valid),.request_ready(controller_ready),
        .write(controller_write),.address(controller_address),.write_data(controller_data),.write_mask(controller_mask),
        .response(controller_response),.read_data(controller_read_data),.initialized(initialized),
        .sdram_a(sdram_a),.sdram_ba(sdram_ba),.sdram_dqm(sdram_dqm),.sdram_cke(sdram_cke),.sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),.sdram_cas_n(sdram_cas_n),.sdram_we_n(sdram_we_n),
        .dq_in(dq_in),.dq_out(dq_out),.dq_oe(dq_oe));
endmodule
