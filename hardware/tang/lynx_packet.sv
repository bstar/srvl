// ASCII requests: opcode + six address hex digits + four data hex digits +
// CRC16-CCITT over those eleven ASCII characters + LF. ASCII avoids the
// BL616 bridge's Ctrl-X/Ctrl-C console escape appearing in game payloads.
module lynx_packet (
    input wire clk, reset,
    input wire [7:0] rx_data,
    input wire rx_valid, rx_error,
    output reg command_valid,
    output reg [7:0] command,
    output reg [23:0] address,
    output reg [15:0] data,
    input wire command_done, command_error,
    input wire [31:0] status,
    output wire [7:0] tx_data,
    output wire tx_valid,
    input wire tx_ready,
    output reg protocol_error
);
    function automatic [15:0] crc_byte(input [15:0] crc, input [7:0] value);
        reg [15:0] c; integer i;
        begin
            c=crc^{value,8'b0};
            for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
            crc_byte=c;
        end
    endfunction
    function automatic [7:0] hexchar(input [3:0] n);
        hexchar=n<10 ? 8'h30+{4'b0,n} : 8'h41+{4'b0,n}-8'd10;
    endfunction
    wire is_hex=(rx_data>="0" && rx_data<="9") || (rx_data>="A" && rx_data<="F") || (rx_data>="a" && rx_data<="f");
    wire [3:0] nibble=rx_data<="9" ? rx_data[3:0] : rx_data[3:0]+4'd9;
    reg [4:0] pos=0;
    reg bad=0, waiting=0, replying=0, reply_error=0;
    reg [15:0] crc=16'hffff, supplied_crc=0, reply_crc=16'hffff;
    reg [3:0] reply_index=0;
    reg [31:0] reply_status;
    reg [7:0] reply_char;
    always @* begin
        if(reply_index==0) reply_char=reply_error ? "E":"K";
        else if(reply_index<9) reply_char=hexchar(reply_status[(8-reply_index)*4 +: 4]);
        else if(reply_index<13) reply_char=hexchar(reply_crc[(12-reply_index)*4 +: 4]);
        else reply_char=8'h0a;
    end
    assign tx_data=reply_char;
    assign tx_valid=replying;
    always @(posedge clk) begin
        command_valid<=0;
        if(reset) begin
            pos<=0; bad<=0; waiting<=0; replying<=0; crc<=16'hffff;
            protocol_error<=0; address<=0; data<=0; command<=0;
        end else begin
            if(rx_error) begin bad<=1; protocol_error<=1; end
            if(command_done && waiting) begin
                waiting<=0; replying<=1; reply_index<=0;
                reply_crc<=16'hffff; reply_status<=status; reply_error<=command_error;
                if(command_error) protocol_error<=1;
            end
            if(replying && tx_ready) begin
                if(reply_index<9) reply_crc<=crc_byte(reply_crc,reply_char);
                if(reply_index==13) replying<=0;
                else reply_index<=reply_index+1;
            end
            if(rx_valid && !waiting && !replying) begin
                if(rx_data==8'h0a) begin
                    pos<=0; bad<=0; crc<=16'hffff;
                    if(pos==15 && !bad && !rx_error && crc==supplied_crc) begin
                        command_valid<=1; waiting<=1;
                    end else if(pos!=0 || bad) begin
                        protocol_error<=1; replying<=1; reply_index<=0;
                        reply_crc<=16'hffff; reply_status<=status; reply_error<=1;
                    end
                end else if(rx_data!=8'h0d) begin
                    if(pos<15) begin
                        pos<=pos+1;
                        if(pos<11) crc<=crc_byte(crc,rx_data);
                        if(pos==0) command<=rx_data;
                        else if(!is_hex) bad<=1;
                        else if(pos<7) address<={address[19:0],nibble};
                        else if(pos<11) data<={data[11:0],nibble};
                        else supplied_crc<={supplied_crc[11:0],nibble};
                    end else bad<=1;
                end
            end
        end
    end
endmodule
