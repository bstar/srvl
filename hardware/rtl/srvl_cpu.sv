// SPDX-License-Identifier: GPL-2.0-or-later
// Stable adapter around the separately licensed, pinned R65C02 implementation.
module srvl_cpu (
    input wire clk, reset,
    input wire [7:0] read_data,
    input wire irq,
    output wire [15:0] address,
    output wire [7:0] write_data,
    output wire write_enable, read_enable, write_n, sync
);
    // Keep the large CPU model independent of pixel-clock scheduling. This
    // changes simulator compilation boundaries, not the hardware or its timing.
    /* verilator hier_block */
    core cpu (
        .clk_clk_i(clk), .rst_rst_n_i(!reset),
        .d_i(read_data), .a_o(address), .d_o(write_data),
        .wr_o(write_enable), .wr_n_o(write_n), .rd_o(read_enable), .sync_o(sync),
        .rdy_i(1'b1), .irq_n_i(!irq), .nmi_n_i(1'b1), .so_n_i(1'b1)
    );
endmodule
