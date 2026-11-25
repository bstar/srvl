// Portable same-clock ready/valid queue. RAM reads are synchronous and there
// are no mixed-port collisions, so the pixel queue can use real block RAM.
// Capacity is 2**ADDRESS_BITS RAM entries plus one registered output entry.
module cb_sync_fifo #(parameter integer WIDTH=32, ADDRESS_BITS=8) (
    input wire clk, reset,
    input wire input_valid,
    output wire input_ready,
    input wire [WIDTH-1:0] input_data,
    output reg output_valid,
    input wire output_ready,
    output reg [WIDTH-1:0] output_data,
    output wire [ADDRESS_BITS:0] level
);
    localparam integer DEPTH=1<<ADDRESS_BITS;
    (* ram_style="block", no_rw_check=1 *) reg [WIDTH-1:0] memory[0:DEPTH-1];
    reg [ADDRESS_BITS-1:0] write_pointer, read_pointer;
    reg [ADDRESS_BITS:0] ram_count;
    assign input_ready=!reset && ram_count<(ADDRESS_BITS+1)'(DEPTH);
    wire push=input_valid && input_ready;
    wire fetch=!reset && ram_count!=0 && (!output_valid || output_ready);
    assign level=ram_count+{{ADDRESS_BITS{1'b0}},output_valid};
    // Keep the RAM's data register free of reset to permit BRAM inference.
    // Output validity, not power-up RAM contents, determines usable data.
    always @(posedge clk) begin
        if(push) memory[write_pointer]<=input_data;
        if(fetch) output_data<=memory[read_pointer];
    end
    always @(posedge clk) begin
        if(reset) begin
            write_pointer<=0; read_pointer<=0; ram_count<=0; output_valid<=0;
        end else begin
            if(push) write_pointer<=write_pointer+1'b1;
            if(fetch) read_pointer<=read_pointer+1'b1;
            case({push,fetch})
                2'b10: ram_count<=ram_count+1'b1;
                2'b01: ram_count<=ram_count-1'b1;
                default: begin end
            endcase
            if(fetch) output_valid<=1;
            else if(output_ready) output_valid<=0;
        end
    end
endmodule
