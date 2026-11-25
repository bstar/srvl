// Three-client, single-outstanding memory service. Ready means ownership was
// accepted into this arbiter, not that the physical memory has completed it.
// A registered request stays coherent through controller/refresh backpressure.
module cb_memory_arbiter (
    input wire clk, reset,
    input wire [2:0] client_valid,
    output reg [2:0] client_ready,
    input wire [2:0] client_write,
    input wire [68:0] client_address,
    input wire [95:0] client_data,
    input wire [11:0] client_mask,
    output wire [2:0] client_response,
    output wire [31:0] client_read_data,
    output reg protocol_fault,
    output reg memory_valid,
    input wire memory_ready,
    output reg memory_write,
    output reg [22:0] memory_address,
    output reg [31:0] memory_data,
    output reg [3:0] memory_mask,
    input wire memory_response,
    input wire [31:0] memory_read_data
);
    reg busy;
    reg [1:0] owner, next_client;
    reg found;
    reg [1:0] selected;
    integer candidate;
    always @* begin
        found=0; selected=0; client_ready=0; candidate=0;
        for(integer offset=0;offset<3;offset=offset+1) begin
            candidate=int'(next_client)+offset;
            if(candidate>=3) candidate=candidate-3;
            if(!found && client_valid[candidate]) begin found=1; selected=2'(candidate); end
        end
        if(!reset && !busy && found) client_ready[selected]=1;
    end
    assign client_response=(busy && !memory_valid && memory_response) ? (3'b001<<owner):3'b000;
    assign client_read_data=memory_read_data;
    always @(posedge clk) begin
        if(reset) begin
            busy<=0; memory_valid<=0; owner<=0; next_client<=0;
            memory_write<=0; memory_address<=0; memory_data<=0; memory_mask<=0;
            protocol_fault<=0;
        end else begin
            if(!busy && found) begin
                busy<=1; owner<=selected;
                next_client<=selected==2 ? 2'd0:selected+1'b1;
                memory_valid<=1;
                memory_write<=client_write[selected];
                memory_address<=client_address[selected*23 +: 23];
                memory_data<=client_data[selected*32 +: 32];
                memory_mask<=client_mask[selected*4 +: 4];
            end
            if(memory_valid && memory_ready) memory_valid<=0;
            if(memory_response) begin
                if(!busy || memory_valid) protocol_fault<=1;
                else busy<=0;
            end
        end
    end
endmodule
