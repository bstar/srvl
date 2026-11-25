// Two scrolling tile planes for the native compositor, held entirely in block
// RAM so that plane fetches add no SDRAM traffic and cannot miss a deadline.
//
// Tile memory, addressed in words by the CPU-side write port:
//   0x0000 + tile*8 + row     pattern row: eight 4-bit pixels, leftmost in 3:0
//   0x1000 + plane*0x800 + ty*64 + tx   map entry (64 x 32 tiles, wraps):
//       7:0 tile, 9:8 reserved, 10 flip X, 11 flip Y, 15:12 palette bank
// Pixel value zero is transparent; otherwise the color index is {bank, pixel}.
//
// A line is produced as a stream: `start` latches the line and the scroll
// values, then each `take` while `valid` advances one pixel. Fetching a tile
// takes a few cycles of this clock; the consumer simply waits for `valid`.
// The write port is a separate clock. Writes are not synchronized to the
// frame: a map changed while it is being displayed shows on later lines.
module cb_tile_planes (
    input wire write_clk, write_enable,
    input wire [12:0] write_address,
    input wire [31:0] write_data,
    input wire clk, reset,
    input wire [1:0] enable,
    input wire [8:0] scroll_x0, scroll_x1,
    input wire [7:0] scroll_y0, scroll_y1,
    input wire start,
    input wire [7:0] line,
    output wire valid,
    input wire take,
    output wire [8:0] back, front
);
    (* ram_style="block", no_rw_check=1 *) reg [31:0] patterns[0:2047];
    (* ram_style="block", no_rw_check=1 *) reg [15:0] maps[0:4095];
    always @(posedge write_clk)
        if(write_enable && write_address[12:11]==2'b00) patterns[write_address[10:0]]<=write_data;
    always @(posedge write_clk)
        if(write_enable && write_address[12]) maps[write_address[11:0]]<=write_data[15:0];

    localparam CHECK=0, MAP=1, ENTRY=2, PATTERN=3, LOAD=4;
    reg [2:0] state;
    reg running, plane;
    reg [1:0] have;
    reg [8:0] world_x[0:1];
    reg [4:0] tile_y[0:1];
    reg [2:0] row[0:1];
    reg [31:0] pixels[0:1];
    reg [4:0] attribute[0:1];          // {flip X, bank}
    reg [15:0] entry, map_word;
    reg [31:0] pattern_word;
    wire _unused_entry=^entry[9:8];
    wire [11:0] map_address={plane,tile_y[plane],world_x[plane][8:3]};
    wire [10:0] pattern_address={entry[7:0],entry[11] ? ~row[plane]:row[plane]};
    // RAM outputs are free of reset so synthesis can infer block RAM.
    always @(posedge clk) begin
        map_word<=maps[map_address];
        pattern_word<=patterns[pattern_address];
    end

    wire [7:0] world_y0=line+scroll_y0;
    wire [7:0] world_y1=line+scroll_y1;
    wire [1:0] ready=have | ~enable;
    assign valid=running && state==CHECK && (&ready);
    function automatic [8:0] candidate(input on, input [31:0] word, input [4:0] attr, input [2:0] fine);
        reg [3:0] pixel;
        begin
            pixel=4'(word>>{fine^{3{attr[4]}},2'b00});
            candidate=(on && pixel!=0) ? {1'b1,attr[3:0],pixel}:9'b0;
        end
    endfunction
    assign back=candidate(enable[0],pixels[0],attribute[0],world_x[0][2:0]);
    assign front=candidate(enable[1],pixels[1],attribute[1],world_x[1][2:0]);

    always @(posedge clk) begin
        if(reset) begin
            state<=CHECK; running<=0; plane<=0; have<=0; entry<=0;
            world_x[0]<=0; world_x[1]<=0; tile_y[0]<=0; tile_y[1]<=0; row[0]<=0; row[1]<=0;
            pixels[0]<=0; pixels[1]<=0; attribute[0]<=0; attribute[1]<=0;
        end else if(start) begin
            state<=CHECK; running<=1; have<=0;
            world_x[0]<=scroll_x0; world_x[1]<=scroll_x1;
            tile_y[0]<=world_y0[7:3]; tile_y[1]<=world_y1[7:3];
            row[0]<=world_y0[2:0]; row[1]<=world_y1[2:0];
        end else case(state)
            CHECK: if(running) begin
                if(!ready[0]) begin plane<=0; state<=MAP; end
                else if(!ready[1]) begin plane<=1; state<=MAP; end
                else if(take) begin
                    world_x[0]<=world_x[0]+1'b1; world_x[1]<=world_x[1]+1'b1;
                    // The next pixel starts a new tile: its pattern must be fetched.
                    if(world_x[0][2:0]==3'd7) have[0]<=0;
                    if(world_x[1][2:0]==3'd7) have[1]<=0;
                end
            end
            MAP: state<=ENTRY;                       // map RAM samples its address
            ENTRY: begin entry<=map_word; state<=PATTERN; end
            PATTERN: state<=LOAD;                    // pattern RAM samples its address
            LOAD: begin
                pixels[plane]<=pattern_word; attribute[plane]<={entry[10],entry[15:12]};
                have[plane]<=1; state<=CHECK;
            end
            default: state<=CHECK;
        endcase
    end
endmodule
