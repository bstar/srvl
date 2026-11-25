// Original 8N1 transport. RX checks the start bit and stop bit; framing errors
// are surfaced rather than silently loading damaged software.
module lynx_uart #(parameter integer CLOCK_HZ=64000000, BAUD=460800) (
    input wire clk, reset, rx,
    output reg tx,
    output reg [7:0] rx_data,
    output reg rx_valid, framing_error,
    input wire [7:0] tx_data,
    input wire tx_valid,
    output wire tx_ready
);
    initial tx=1;
    localparam integer DIV=(CLOCK_HZ+BAUD/2)/BAUD;
    reg [1:0] rx_sync=3;
    always @(posedge clk) rx_sync <= {rx_sync[0],rx};
    reg [15:0] rx_count=0, tx_count=0;
    reg [2:0] rx_bit=0;
    reg [3:0] tx_bit=0;
    reg [7:0] rx_shift=0;
    reg [8:0] tx_shift=9'h1ff;
    reg [1:0] rx_state=0;
    reg tx_busy=0;
    assign tx_ready=!tx_busy;
    always @(posedge clk) begin
        rx_valid<=0; framing_error<=0;
        if (reset) begin
            rx_state<=0; rx_count<=0; tx_busy<=0; tx<=1;
        end else begin
            case(rx_state)
                0: if (!rx_sync[1]) begin rx_count<=16'(DIV/2); rx_state<=1; end
                1: if (rx_count!=0) rx_count<=rx_count-1;
                   else if (!rx_sync[1]) begin rx_count<=16'(DIV-1); rx_bit<=0; rx_state<=2; end
                   else rx_state<=0;
                2: if (rx_count!=0) rx_count<=rx_count-1;
                   else begin
                       rx_shift[rx_bit]<=rx_sync[1]; rx_count<=16'(DIV-1);
                       if(rx_bit==7) rx_state<=3; else rx_bit<=rx_bit+1;
                   end
                3: if (rx_count!=0) rx_count<=rx_count-1;
                   else begin
                       rx_state<=0;
                       if(rx_sync[1]) begin rx_data<=rx_shift; rx_valid<=1; end
                       else framing_error<=1;
                   end
            endcase
            if (!tx_busy) begin
                if(tx_valid) begin
                    tx_shift<={1'b1,tx_data}; tx<=0;
                    tx_bit<=0; tx_count<=16'(DIV-1); tx_busy<=1;
                end
            end else if(tx_count!=0) tx_count<=tx_count-1;
            else begin
                tx_count<=16'(DIV-1);
                if(tx_bit==9) begin tx_busy<=0; tx<=1; end
                else begin tx_shift<={1'b1,tx_shift[8:1]}; tx<=tx_shift[0]; tx_bit<=tx_bit+1; end
            end
        end
    end
endmodule
