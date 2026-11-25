// Shared loader/cart service ahead of the SDRAM controller. Cartridge requests
// are pulses; latch misses until granted. One aligned-word cache serves byte
// reads without changing the console's own bus/interrupt timing logic.
module lynx_cart_bridge (
    input wire clk, reset, running,
    input wire load_request,
    input wire [22:0] load_address,
    input wire [31:0] load_data,
    input wire [3:0] load_mask,
    output wire load_ready,
    output reg load_response,
    input wire cart_request,
    input wire [19:0] cart_address,
    output reg cart_ack,
    output reg [7:0] cart_byte,
    output reg protocol_fault,
    output wire memory_request,
    input wire memory_ready, memory_response,
    input wire [31:0] memory_read_data,
    output wire memory_write,
    output wire [22:0] memory_address,
    output wire [31:0] memory_data,
    output wire [3:0] memory_mask
);
    initial protocol_fault=0;
    localparam NONE=0, LOAD=1, CART=2;
    reg [1:0] owner=NONE;
    reg pending=0, cache_valid=0;
    reg [19:0] pending_address=0, issued_address=0;
    reg [17:0] cache_address=0;
    reg [31:0] cache_data=0;
    wire loading=load_request && !running;
    assign memory_request=owner==NONE && (loading || (pending && running));
    assign memory_write=loading;
    assign memory_address=loading ? load_address:{3'b0,pending_address};
    assign memory_data=load_data;
    assign memory_mask=load_mask;
    assign load_ready=owner==NONE && !running && memory_ready;
    always @(posedge clk) begin
        load_response<=0; cart_ack<=0;
        if(reset) begin
            owner<=NONE; pending<=0; cache_valid<=0; protocol_fault<=0; cart_byte<=0;
        end else begin
            if(!running) begin pending<=0; cache_valid<=0; end
            else if(cart_request) begin
                if(pending || owner==CART) protocol_fault<=1;
                else if(cache_valid && cache_address==cart_address[19:2]) begin
                    cart_byte<=cache_data[cart_address[1:0]*8 +: 8]; cart_ack<=1;
                end else begin pending_address<=cart_address; pending<=1; end
            end
            if(memory_request && memory_ready) begin
                if(loading) begin owner<=LOAD; cache_valid<=0; end
                else begin owner<=CART; issued_address<=pending_address; pending<=0; end
            end
            if(memory_response) begin
                if(owner==LOAD) load_response<=1;
                else if(owner==CART && running) begin
                    cache_address<=issued_address[19:2]; cache_data<=memory_read_data;
                    cache_valid<=1;
                    cart_byte<=memory_read_data[issued_address[1:0]*8 +: 8]; cart_ack<=1;
                end else if(owner==NONE) protocol_fault<=1;
                owner<=NONE;
            end
        end
    end
endmodule
