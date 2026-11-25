// Component fixture: original capture/scanout + real arbiter/controller. The
// third client deliberately competes with video; no Lynx source is fabricated.
module tang_video_top (
    input wire clk, reset, video_clk, video_reset, enable, memory_stall,
    input wire pixel_write,
    input wire [13:0] pixel_address,
    input wire [11:0] pixel_data,
    input wire host_valid, host_write,
    input wire [22:0] host_address,
    input wire [31:0] host_data,
    input wire [3:0] host_mask,
    output wire host_ready, host_response,
    output wire [31:0] host_read_data,
    output wire display_valid, present,
    output wire [1:0] display_bank,
    output wire overflow, capture_fault, scan_fault, arbiter_fault,
    output wire [15:0] dropped_frames, underrun_count,
    output wire [11:0] video_rgb,
    output wire video_de, video_hsync, video_vsync, video_frame_valid,
    output wire [9:0] video_x, video_y,
    output wire memory_valid, memory_ready, memory_write,
    output wire [22:0] memory_address,
    output wire [31:0] memory_data,
    output wire [3:0] memory_mask,
    output wire [10:0] sdram_a,
    output wire [1:0] sdram_ba,
    output wire [3:0] sdram_dqm,
    output wire sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n,
    input wire [31:0] dq_in,
    output wire [31:0] dq_out,
    output wire dq_oe
);
    wire capture_valid, capture_ready, capture_response, frame_ready;
    wire [22:0] capture_address, scan_address;
    wire [31:0] capture_data, read_data;
    wire [3:0] capture_mask;
    wire scan_valid, scan_ready, scan_response, response, controller_ready, initialized;
    wire [2:0] clients_ready, clients_response;
    wire _unused_underrun;
    wire _unused_status=frame_ready ^ initialized;
    lynx_frame_capture capture (.clk(clk),.reset(reset),.enable(enable),
        .pixel_write(pixel_write),.pixel_address(pixel_address),.pixel_data(pixel_data),.present(present),
        .display_valid(display_valid),.display_bank(display_bank),.frame_ready(frame_ready),
        .overflow(overflow),.capture_error(capture_fault),.dropped_frames(dropped_frames),
        .write_valid(capture_valid),.write_ready(capture_ready),.write_response(capture_response),
        .write_address(capture_address),.write_data(capture_data),.write_mask(capture_mask));
    lynx_scanout scanout (.clk(clk),.reset(reset),.video_clk(video_clk),.video_reset(video_reset),
        .display_valid(display_valid),.display_bank(display_bank),.present(present),
        .read_valid(scan_valid),.read_ready(scan_ready),.read_response(scan_response),
        .read_address(scan_address),.read_data(read_data),
        .video_rgb(video_rgb),.video_de(video_de),.video_hsync(video_hsync),.video_vsync(video_vsync),
        .video_x(video_x),.video_y(video_y),.video_frame_valid(video_frame_valid),
        .underrun(_unused_underrun),.underrun_count(underrun_count),.protocol_fault(scan_fault));
    assign {scan_ready,capture_ready,host_ready}=clients_ready;
    assign {scan_response,capture_response,host_response}=clients_response;
    assign host_read_data=read_data;
    assign memory_ready=controller_ready && !memory_stall;
    cb_graphics_arbiter arbiter (.clk(clk),.reset(reset),
        .client_valid({scan_valid,capture_valid,host_valid}),.client_ready(clients_ready),
        .client_write({1'b0,1'b1,host_write}),.client_address({scan_address,capture_address,host_address}),
        .client_data({32'b0,capture_data,host_data}),.client_mask({4'b0,capture_mask,host_mask}),
        .client_response(clients_response),.client_read_data(read_data),.protocol_fault(arbiter_fault),
        .memory_valid(memory_valid),.memory_ready(memory_ready),.memory_write(memory_write),
        .memory_address(memory_address),.memory_data(memory_data),.memory_mask(memory_mask),
        .memory_response(response),.memory_read_data(host_read_data_internal));
    wire [31:0] host_read_data_internal;
    cb_graphics_sdram memory (.clk(clk),.reset(reset),.request(memory_valid && !memory_stall),.request_ready(controller_ready),
        .write(memory_write),.address(memory_address),.write_data(memory_data),.write_mask(memory_mask),
        .response(response),.read_data(host_read_data_internal),.initialized(initialized),
        .sdram_a(sdram_a),.sdram_ba(sdram_ba),.sdram_dqm(sdram_dqm),.sdram_cke(sdram_cke),.sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),.sdram_cas_n(sdram_cas_n),.sdram_we_n(sdram_we_n),
        .dq_in(dq_in),.dq_out(dq_out),.dq_oe(dq_oe));
endmodule
