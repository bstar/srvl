// Test-only integration: optional actual R65C02 + local ROM/RAM, experimental
// dual-clock MMIO, real blitter/arbiter/SDRAM, and synthetic front-read traffic.
module native_graphics_top #(
    parameter integer USE_CPU=1,
    parameter ROM_FILE="native-graphics.hex"
) (
    input wire clk, cpu_clk, reset, memory_stall, test_fault,
    // The test bus is used only when USE_CPU=0.
    /* verilator lint_off UNUSEDSIGNAL */
    input wire [7:0] test_bus_address, test_bus_data,
    input wire test_bus_write,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [7:0] test_read_data,
    output wire irq, initialized, protocol_fault,
    output wire [7:0] diagnostic,
    output wire [15:0] trace_address,
    output wire [7:0] trace_data,
    output wire trace_write, trace_sync,
    input wire peer_valid,
    input wire [22:0] peer_address,
    output wire peer_ready, peer_response,
    output wire [31:0] peer_read_data,
    output wire [10:0] sdram_a,
    output wire [1:0] sdram_ba,
    output wire [3:0] sdram_dqm,
    output wire sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n,
    input wire [31:0] dq_in,
    output wire [31:0] dq_out,
    output wire dq_oe
);
    wire [15:0] address;
    wire [7:0] write_data, register_data;
    wire write_enable, sync;
    generate if(USE_CPU!=0) begin: actual_cpu
        reg [7:0] ram [0:8191];
        reg [7:0] rom [0:32767];
        initial $readmemh(ROM_FILE,rom);
        reg [7:0] read_data;
        reg [7:0] result;
        wire _unused_write_n, _unused_read_enable;
        core cpu (.clk_clk_i(cpu_clk),.rst_rst_n_i(!reset),.d_i(read_data),.a_o(address),.d_o(write_data),
            .wr_o(write_enable),.wr_n_o(_unused_write_n),.rd_o(_unused_read_enable),.sync_o(sync),
            .rdy_i(1'b1),.irq_n_i(!irq),.nmi_n_i(1'b1),.so_n_i(1'b1));
        always @* begin
            if(address[15]) read_data=rom[address[14:0]];
            else if(address<16'h2000) read_data=ram[address[12:0]];
            else if(address[15:8]==8'h44) read_data=register_data;
            else read_data=0;
        end
        always @(posedge cpu_clk) begin
            if(reset) result<=0;
            else if(write_enable) begin
                if(address<16'h2000) ram[address[12:0]]<=write_data;
                if(address==16'h403f) result<=write_data;
            end
        end
        assign diagnostic=result;
    end else begin: register_driver
        assign address={8'h44,test_bus_address};
        assign write_data=test_bus_data;
        assign write_enable=test_bus_write;
        assign sync=0;
        assign diagnostic=0;
    end endgenerate
    assign trace_address=address;
    assign trace_data=write_data;
    assign trace_write=write_enable && !reset;
    assign trace_sync=sync && !reset;
    assign test_read_data=register_data;
    wire memory_valid, memory_ready, memory_write, memory_response;
    wire [22:0] memory_address;
    wire [31:0] memory_data, memory_read_data;
    wire [3:0] memory_mask;
    wire byte_valid, byte_ready, byte_write, byte_response;
    wire [22:0] byte_address;
    wire [31:0] byte_data, byte_read_data;
    wire [3:0] byte_mask;
    wire arbiter_fault;
    cb_blitter_mmio registers (.cpu_clk(cpu_clk),.graphics_clk(clk),.reset(reset),
        .bus_address(address[7:0]),.bus_write_data(write_data),.bus_write(write_enable && address[15:8]==8'h44 && !reset),
        .bus_read_data(register_data),.irq(irq),.initialized(initialized),
        .external_protocol_fault(arbiter_fault || test_fault),.protocol_fault(protocol_fault),
        .memory_valid(memory_valid),.memory_ready(memory_ready),.memory_write(memory_write),.memory_address(memory_address),
        .memory_data(memory_data),.memory_mask(memory_mask),.memory_response(memory_response),.memory_read_data(memory_read_data),
        .byte_valid(byte_valid),.byte_ready(byte_ready),.byte_write(byte_write),.byte_address(byte_address),
        .byte_data(byte_data),.byte_mask(byte_mask),.byte_response(byte_response),.byte_read_data(byte_read_data));
    wire controller_valid, controller_ready, controller_write, controller_response;
    wire [22:0] controller_address;
    wire [31:0] controller_data, controller_read_data, shared_read_data;
    wire [3:0] controller_mask;
    wire [2:0] ready, response;
    assign {peer_ready,memory_ready,byte_ready}=ready;
    assign {peer_response,memory_response,byte_response}=response;
    assign memory_read_data=shared_read_data;
    assign byte_read_data=shared_read_data;
    assign peer_read_data=shared_read_data;
    cb_graphics_arbiter arbiter (.clk(clk),.reset(reset),
        .client_valid({peer_valid,memory_valid,byte_valid}),.client_ready(ready),
        .client_write({1'b0,memory_write,byte_write}),.client_address({peer_address,memory_address,byte_address}),
        .client_data({32'b0,memory_data,byte_data}),.client_mask({4'b0,memory_mask,byte_mask}),
        .client_response(response),.client_read_data(shared_read_data),.protocol_fault(arbiter_fault),
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
