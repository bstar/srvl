// Test-only pin/stall/fault fixture around the real enhanced memory service.
module graphics_memory_top (
    input wire clk, reset, memory_stall, force_response,
    input wire [2:0] client_valid, client_write,
    output wire [2:0] client_ready, client_response,
    input wire [68:0] client_address,
    input wire [95:0] client_data,
    input wire [11:0] client_mask,
    output wire [31:0] client_read_data,
    output wire initialized, protocol_fault,
    output wire controller_valid, controller_ready, controller_response, controller_write,
    output wire [22:0] controller_address,
    output wire [31:0] controller_data,
    output wire [3:0] controller_mask,
    output wire [10:0] sdram_a,
    output wire [1:0] sdram_ba,
    output wire [3:0] sdram_dqm,
    output wire sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n,
    input wire [31:0] dq_in,
    output wire [31:0] dq_out,
    output wire dq_oe
);
    wire [31:0] controller_read_data;
    cb_graphics_arbiter arbiter (.clk(clk),.reset(reset),
        .client_valid(client_valid),.client_ready(client_ready),.client_write(client_write),
        .client_address(client_address),.client_data(client_data),.client_mask(client_mask),
        .client_response(client_response),.client_read_data(client_read_data),.protocol_fault(protocol_fault),
        .memory_valid(controller_valid),.memory_ready(controller_ready && !memory_stall),
        .memory_write(controller_write),.memory_address(controller_address),.memory_data(controller_data),.memory_mask(controller_mask),
        .memory_response(controller_response || force_response),.memory_read_data(controller_read_data));
    cb_graphics_sdram memory (.clk(clk),.reset(reset),
        .request(controller_valid && !memory_stall),.request_ready(controller_ready),
        .write(controller_write),.address(controller_address),.write_data(controller_data),.write_mask(controller_mask),
        .response(controller_response),.read_data(controller_read_data),.initialized(initialized),
        .sdram_a(sdram_a),.sdram_ba(sdram_ba),.sdram_dqm(sdram_dqm),.sdram_cke(sdram_cke),.sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),.sdram_cas_n(sdram_cas_n),.sdram_we_n(sdram_we_n),
        .dq_in(dq_in),.dq_out(dq_out),.dq_oe(dq_oe));
endmodule
