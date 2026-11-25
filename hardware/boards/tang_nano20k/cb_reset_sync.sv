// Asynchronous assertion, three local rising edges before reset release.
module cb_reset_sync (
    input wire clk, async_reset,
    output wire reset
);
    // A reset synchronizer's output is by design asynchronously set and
    // then used as a synchronous reset by its domain.
    /* verilator lint_off SYNCASYNCNET */
    (* ASYNC_REG="TRUE" *) reg [2:0] stages;
    /* verilator lint_on SYNCASYNCNET */
    // FPGA configuration must begin in reset even before a reference edge.
    initial stages=3'b111;
    always @(posedge clk or posedge async_reset)
        if(async_reset) stages<=3'b111;
        else stages<={stages[1:0],1'b0};
    assign reset=stages[2];
endmodule
