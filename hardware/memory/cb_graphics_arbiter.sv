// Original enhanced three-client memory arbiter. One elastic request slot:
// bypass when the controller is ready, retain accepted work during recovery,
// and retire an old response while accepting the next owner on the same edge.
// Shared by the legacy Lynx system and the enhanced engines. Responses must
// follow acceptance.
module cb_graphics_arbiter (
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
    output wire memory_valid,
    input wire memory_ready,
    output wire memory_write,
    output wire [22:0] memory_address,
    output wire [31:0] memory_data,
    output wire [3:0] memory_mask,
    input wire memory_response,
    input wire [31:0] memory_read_data
);
    reg occupied, pending;
    reg [1:0] owner, next_client;
    reg saved_write;
    reg [22:0] saved_address;
    reg [31:0] saved_data;
    reg [3:0] saved_mask;
    reg found;
    reg [1:0] selected;
    integer candidate;
    wire retiring=occupied && !pending && memory_response;
    wire space=!occupied || retiring;
    wire bypass=space && found;
    wire use_saved=pending || (occupied && !retiring);
    always @* begin
        found=0; selected=0; candidate=0; client_ready=0;
        for(integer offset=0;offset<3;offset=offset+1) begin
            candidate=int'(next_client)+offset;
            if(candidate>=3) candidate=candidate-3;
            if(!found && client_valid[candidate]) begin found=1; selected=2'(candidate); end
        end
        if(!reset && space && found) client_ready[selected]=1;
    end
    assign memory_valid=!reset && (pending || bypass);
    assign memory_write=use_saved ? saved_write:client_write[selected];
    assign memory_address=use_saved ? saved_address:client_address[selected*23 +: 23];
    assign memory_data=use_saved ? saved_data:client_data[selected*32 +: 32];
    assign memory_mask=use_saved ? saved_mask:client_mask[selected*4 +: 4];
    assign client_response=(!reset && retiring) ? (3'b001<<owner):3'b000;
    assign client_read_data=memory_read_data;
    always @(posedge clk) begin
        if(reset) begin
            occupied<=0; pending<=0; owner<=0; next_client<=0;
            saved_write<=0; saved_address<=0; saved_data<=0; saved_mask<=0; protocol_fault<=0;
        end else begin
            if(memory_response) begin
                if(!occupied || pending) protocol_fault<=1;
                else occupied<=0;
            end
            if(pending && memory_ready) pending<=0;
            if(bypass) begin
                occupied<=1; pending<=!memory_ready; owner<=selected;
                next_client<=selected==2 ? 2'd0:selected+1'b1;
                saved_write<=client_write[selected]; saved_address<=client_address[selected*23 +: 23];
                saved_data<=client_data[selected*32 +: 32]; saved_mask<=client_mask[selected*4 +: 4];
            end
        end
    end
endmodule
