// Original stop-and-wait loader for the pinned Lynx console. The CPU remains
// reset until a valid complete image has reached memory and the header/RAM
// loader has consumed its last word. No command writes a running game.
module lynx_loader (
    input wire clk, reset,
    input wire command_valid,
    input wire [7:0] command,
    input wire [23:0] address,
    input wire [15:0] data,
    output reg command_done, command_error,
    input wire memory_initialized, protocol_error,
    input wire [6:0] presentation_status,
    output wire [31:0] status,
    output reg running, loading, bios_valid, image_valid,
    output reg [8:0] buttons,
    output reg [19:0] romsize,
    output reg [20:0] image_bytes,
    output wire memory_request,
    input wire memory_ready, memory_response,
    output wire [22:0] memory_address,
    output wire [31:0] memory_data,
    output wire [3:0] memory_mask,
    output reg [8:0] bios_address,
    output reg [7:0] bios_data,
    output reg bios_write,
    output reg [19:0] rom_address,
    output reg [15:0] rom_data,
    output reg rom_write
);
    initial begin
        running=0; loading=0; bios_valid=0; image_valid=0;
        buttons=0; romsize=0; image_bytes=0;
    end
    localparam IDLE=0, WRITE_REQUEST=1, WRITE_WAIT=2, HEADER_WAIT=3, BIOS_WAIT=4;
    reg [2:0] state=IDLE;
    reg [3:0] settle=0;
    reg [9:0] bios_bytes=0;
    reg [7:0] last_bios=0;
    reg [15:0] header0=0, header1=0, header2=0, header3=0, header4=0;
    wire bs93 = header3==16'h5342 && header4==16'h3339;
    wire lnx = header0==16'h594c && header1==16'h584e;
    wire [15:0] entry_address={header1[7:0],header1[15:8]};
    wire [15:0] bs93_bytes={header2[7:0],header2[15:8]};
    wire [20:0] size_requested={1'b0,address[19:0]}+21'd1;
    wire raw_size=size_requested==65536 || size_requested==131072 ||
                  size_requested==262144 || size_requested==524288;
    wire lnx_size=(header2==16'h0100 || header2==16'h0200 ||
                   header2==16'h0400 || header2==16'h0800) &&
                  size_requested==({5'b0,header2}<<8)+21'd64 &&
                  header3==0 && header4==1;
    wire bs93_size=bs93_bytes!=0 && !bs93_bytes[0] && entry_address!=0 &&
                   ({1'b0,entry_address}+{1'b0,bs93_bytes})<=17'd65536 &&
                   size_requested=={5'b0,bs93_bytes}+21'd10;
    assign memory_request=state==WRITE_REQUEST;
    assign memory_address={3'b0,rom_address};
    assign memory_data={rom_data,rom_data};
    assign memory_mask=rom_address[1] ? 4'b1100:4'b0011;
    // Bits 0..7: memory ready, BIOS valid, running, image valid, loading,
    // protocol error, reserved, reserved. Bits 8..12 belong to presentation.
    assign status={16'h4c59,1'b0,presentation_status,2'b0,protocol_error,
                   loading,image_valid,running,bios_valid,memory_initialized};
    always @(posedge clk) begin
        command_done<=0; command_error<=0; bios_write<=0; rom_write<=0;
        if(reset) begin
            state<=IDLE; running<=0; loading<=0; bios_valid<=0;
            image_valid<=0; bios_bytes<=0; image_bytes<=0; buttons<=0;
            romsize<=0; rom_address<=0; rom_data<=0;
            bios_address<=0; bios_data<=0; last_bios<=0;
            header0<=0; header1<=0; header2<=0; header3<=0; header4<=0;
        end else begin
            case(state)
                WRITE_REQUEST: if(memory_ready) state<=WRITE_WAIT;
                WRITE_WAIT: if(memory_response) begin
                    // Header.vhd observes this pulse on the following edge;
                    // keep address/data stable while it emits both RAM bytes.
                    rom_write<=1; settle<=7; state<=HEADER_WAIT;
                end
                HEADER_WAIT: if(settle!=0) settle<=settle-1;
                    else begin
                        image_bytes<=image_bytes+2; command_done<=1; state<=IDLE;
                    end
                BIOS_WAIT: begin command_done<=1; state<=IDLE; end
                IDLE: if(command_valid) begin
                    command_done<=1;
                    case(command)
                        "Q": if(address!=0 || data!=0) command_error<=1;
                        "L": if(address!=0 || data!=0) command_error<=1;
                            else begin
                                running<=0; loading<=1; image_valid<=0;
                                image_bytes<=0; buttons<=0;
                                header0<=0; header1<=0; header2<=0; header3<=0; header4<=0;
                            end
                        "B": if(running || !loading || address>=512 || data[15:8]!=0)
                                command_error<=1;
                            else if(bios_bytes!=0 && address=={14'b0,bios_bytes}-24'd1 && data[7:0]==last_bios) begin
                                // Idempotent retransmission after an ACK was lost.
                            end else if(address==0 || (address=={14'b0,bios_bytes} && bios_bytes<512)) begin
                                if(address==0) begin bios_bytes<=1; bios_valid<=0; end
                                else begin bios_bytes<=bios_bytes+1; if(address==511) bios_valid<=1; end
                                bios_address<=address[8:0]; bios_data<=data[7:0];
                                last_bios<=data[7:0]; bios_write<=1;
                                command_done<=0; state<=BIOS_WAIT;
                            end else command_error<=1;
                        "W": if(running || !loading || !memory_initialized || address[23:20]!=0 || address[0])
                                command_error<=1;
                            else if(image_bytes>=2 && {1'b0,address[19:0]}==image_bytes-2 && data==rom_data) begin
                                // The already committed previous word is not written twice.
                            end else if({1'b0,address[19:0]}!=image_bytes || image_bytes>=21'h100000)
                                command_error<=1;
                            else begin
                                rom_address<=address[19:0]; rom_data<=data;
                                case(address[19:0])
                                    0: header0<=data;
                                    2: header1<=data;
                                    4: header2<=data;
                                    6: header3<=data;
                                    8: header4<=data;
                                    default: begin end
                                endcase
                                command_done<=0; state<=WRITE_REQUEST;
                            end
                        "C": if(data!=0 || address[23:20]!=0) command_error<=1;
                            else if(running && image_valid && address[19:0]==romsize) begin
                                // An ACK retry must not generate a second launch/reset.
                            end else if(!loading || !memory_initialized || image_bytes!=size_requested ||
                                        image_bytes<10 || !(bs93 ? bs93_size : bios_valid && (lnx ? lnx_size : raw_size)))
                                command_error<=1;
                            else begin
                                romsize<=address[19:0]; image_valid<=1;
                                loading<=0; running<=1; buttons<=0;
                            end
                        "K": if(address!=0 || data[15:9]!=0 || !running) command_error<=1;
                            else buttons<=data[8:0];
                        "R": if(address!=0 || data!=0) command_error<=1;
                            else begin running<=0; loading<=0; buttons<=0; image_valid<=0; end
                        default: command_error<=1;
                    endcase
                end
                default: begin state<=IDLE; running<=0; loading<=0; image_valid<=0; end
            endcase
        end
    end
endmodule
