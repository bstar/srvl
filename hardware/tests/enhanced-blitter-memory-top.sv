// Integration fixture: real blitter, round-robin service and x32 SDRAM controller.
// Peer traffic models front-surface reads; no native scanout/CPU is claimed.
module enhanced_blitter_memory_top (
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
    output wire memory_ready,
    output wire memory_write,
    output wire [22:0] memory_address,
    output wire [31:0] memory_data,
    output wire [3:0] memory_mask,
    output wire memory_response,
    output wire [31:0] memory_read_data,

    input wire memory_stall,
    input wire host_valid, host_write,
    input wire [22:0] host_address,
    input wire [31:0] host_data,
    input wire [3:0] host_mask,
    output wire host_ready, host_response,
    output wire [31:0] host_read_data,
    input wire peer_valid,
    input wire [22:0] peer_address,
    output wire peer_ready, peer_response,
    output wire [31:0] peer_read_data,
    output wire initialized, arbiter_fault,
    output wire [10:0] sdram_a,
    output wire [1:0] sdram_ba,
    output wire [3:0] sdram_dqm,
    output wire sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n,
    input wire [31:0] dq_in,
    output wire [31:0] dq_out,
    output wire dq_oe
);

    cb_scaled_blitter engine (.*);
    wire controller_valid, controller_ready, controller_response, controller_write;
    wire [22:0] controller_address;
    wire [31:0] controller_data, controller_read_data;
    wire [3:0] controller_mask;
    wire [2:0] clients_ready, clients_response;
    wire [31:0] shared_read_data;
    assign {peer_ready,memory_ready,host_ready}=clients_ready;
    assign {peer_response,memory_response,host_response}=clients_response;
    assign memory_read_data=shared_read_data;
    assign host_read_data=shared_read_data;
    assign peer_read_data=shared_read_data;
    cb_graphics_arbiter arbiter (.clk(clk),.reset(reset),
        .client_valid({peer_valid,memory_valid,host_valid}),.client_ready(clients_ready),
        .client_write({1'b0,memory_write,host_write}),
        .client_address({peer_address,memory_address,host_address}),
        .client_data({32'b0,memory_data,host_data}),.client_mask({4'b0,memory_mask,host_mask}),
        .client_response(clients_response),.client_read_data(shared_read_data),.protocol_fault(arbiter_fault),
        .memory_valid(controller_valid),.memory_ready(controller_ready && !memory_stall),
        .memory_write(controller_write),.memory_address(controller_address),.memory_data(controller_data),.memory_mask(controller_mask),
        .memory_response(controller_response),.memory_read_data(controller_read_data));
    cb_graphics_sdram memory (.clk(clk),.reset(reset),.request(controller_valid && !memory_stall),.request_ready(controller_ready),
        .write(controller_write),.address(controller_address),.write_data(controller_data),.write_mask(controller_mask),
        .response(controller_response),.read_data(controller_read_data),.initialized(initialized),
        .sdram_a(sdram_a),.sdram_ba(sdram_ba),.sdram_dqm(sdram_dqm),.sdram_cke(sdram_cke),.sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),.sdram_cas_n(sdram_cas_n),.sdram_we_n(sdram_we_n),
        .dq_in(dq_in),.dq_out(dq_out),.dq_oe(dq_oe));
endmodule
