// Original implementation of DVI 1.0 section 3.2.2. Output is one registered
// 10-bit word, sent least-significant bit first. Blanking resets disparity.
module cb_tmds_encoder (
    input wire clk, reset, de, c0, c1,
    input wire [7:0] data,
    output reg [9:0] symbol
);
    reg [3:0] data_ones, chain_ones;
    reg [8:0] chain;
    reg xnor_mode;
    integer i;
    always @* begin
        data_ones=0;
        for(integer bit_n=0;bit_n<8;bit_n=bit_n+1) data_ones=data_ones+{3'b0,data[bit_n]};
        xnor_mode=data_ones>4 || (data_ones==4 && !data[0]);
        chain[0]=data[0];
        for(i=1;i<8;i=i+1) chain[i]=chain[i-1]^data[i]^xnor_mode;
        chain[8]=!xnor_mode;
        chain_ones=0;
        for(integer bit_n=0;bit_n<8;bit_n=bit_n+1) chain_ones=chain_ones+{3'b0,chain[bit_n]};
    end
    reg signed [5:0] disparity;
    wire signed [5:0] balance=$signed({1'b0,chain_ones,1'b0})-6'sd8;
    always @(posedge clk) begin
        if(reset) begin symbol<=10'b1101010100; disparity<=0; end
        else if(!de) begin
            disparity<=0;
            case({c1,c0})
                2'b00: symbol<=10'b1101010100;
                2'b01: symbol<=10'b0010101011;
                2'b10: symbol<=10'b0101010100;
                2'b11: symbol<=10'b1010101011;
            endcase
        end else if(disparity==0 || balance==0) begin
            symbol<={!chain[8],chain[8],chain[8] ? chain[7:0]:~chain[7:0]};
            disparity<=disparity+(chain[8] ? balance:-balance);
        end else if((disparity>0 && balance>0) || (disparity<0 && balance<0)) begin
            symbol<={1'b1,chain[8],~chain[7:0]};
            disparity<=disparity+(chain[8] ? 6'sd2:6'sd0)-balance;
        end else begin
            symbol<={1'b0,chain[8],chain[7:0]};
            disparity<=disparity+balance-(chain[8] ? 6'sd0:6'sd2);
        end
    end
endmodule
