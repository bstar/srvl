// SPDX-License-Identifier: GPL-2.0-or-later
// Prototype custom video/audio/input hardware. One 6.288 MHz clock; 60 Hz frames.
module chipbuilder_peripherals #(
    parameter FONT_FILE = "font.hex",
    parameter SPRITE_FILE = "sprites.hex"
) (
    input wire clk, reset,
    input wire [15:0] address,
    input wire [7:0] write_data,
    input wire write_enable, read_enable,
    output reg [7:0] read_data,
    input wire [7:0] buttons,
    output wire irq,
    output reg cpu_sleep = 0,
    output wire [7:0] red, green, blue,
    output wire de, hsync, vsync,
    output wire [8:0] video_x, video_y,
    output wire [15:0] audio_left, audio_right,
    output reg [15:0] frame_count = 0,
    output reg [7:0] diagnostic = 0
);
    // Separate tile/attribute banks permit simultaneous one-clock video fetches.
    // Firmware initializes VRAM before enabling the display.
    reg [7:0] tiles [0:2047];
    reg [7:0] attributes [0:2047];
    reg [7:0] font_rom [0:2047];
    reg [31:0] sprite_rom [0:127];
    initial begin
        $readmemh(FONT_FILE, font_rom);
        $readmemh(SPRITE_FILE, sprite_rom);
    end
    reg [11:0] palette [0:15];
    reg [7:0] sprites [0:63];
    reg video_enable = 0;
    reg irq_enable = 0, irq_pending = 0;
    reg [7:0] latched_buttons = 0;
    reg [15:0] tone_step [0:1];
    reg [3:0] tone_volume [0:1];
    reg tone_gate [0:1];
    reg [23:0] tone_phase [0:1];
    // Two independent millisecond stopwatches: level time and campaign score.
    // 6.288 MHz / 6288 is exactly 1 kHz. Low-byte reads snapshot the upper bytes.
    reg timer_running [0:1];
    reg [12:0] timer_divider [0:1];
    reg [23:0] timer_ms [0:1];
    reg [15:0] timer_snapshot [0:1];
    reg [8:0] h = 0, v = 0;
    wire frame_end = h == 9'd399 && v == 9'd261;
    wire vblank_start = h == 0 && v == 9'd204;
    assign irq = irq_enable && irq_pending;

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            h <= 0; v <= 0; frame_count <= 0;
            video_enable <= 0;
            irq_enable <= 0; irq_pending <= 0; latched_buttons <= 0;
            cpu_sleep <= 0;
            diagnostic <= 0;
            for (i=0; i<16; i=i+1) palette[i] <= 0;
            for (i=0; i<64; i=i+1) sprites[i] <= 0;
            for (i=0; i<2; i=i+1) begin
                timer_running[i] <= 0; timer_divider[i] <= 0;
                timer_ms[i] <= 0; timer_snapshot[i] <= 0;
                tone_step[i] <= 0; tone_volume[i] <= 0;
                tone_gate[i] <= 0; tone_phase[i] <= 0;
            end
        end else begin
            if (h == 9'd399) begin
                h <= 0;
                if (v == 9'd261) v <= 0;
                else v <= v + 9'd1;
            end else h <= h + 9'd1;
            if (frame_end) frame_count <= frame_count + 16'd1;
            if (vblank_start) begin
                irq_pending <= 1;
                latched_buttons <= buttons;
                cpu_sleep <= 0;
            end
            for (i=0; i<2; i=i+1) begin
                tone_phase[i] <= tone_phase[i] + {8'd0,tone_step[i]};
                if (timer_running[i] && timer_ms[i] < 24'd5999999) begin
                    if (timer_divider[i] == 13'd6287) begin
                        timer_divider[i] <= 0;
                        timer_ms[i] <= timer_ms[i] + 24'd1;
                    end else timer_divider[i] <= timer_divider[i] + 13'd1;
                end
            end
            if (read_enable && address >= 16'h4040 && address < 16'h4048 && address[1:0] == 2'd1)
                timer_snapshot[address[2]] <= timer_ms[address[2]][23:8];
            if (write_enable) begin
                if (address == 16'h4040 || address == 16'h4044) begin
                    timer_running[address[2]] <= write_data[0];
                    if (write_data[1]) begin
                        timer_divider[address[2]] <= 0;
                        timer_ms[address[2]] <= 0;
                        timer_snapshot[address[2]] <= 0;
                    end
                end
                if (address[15:12] == 4'h2) begin
                    if (address[11]) attributes[address[10:0]] <= write_data;
                    else tiles[address[10:0]] <= write_data;
                end
                if (address[15:5] == 11'h200) begin
                    if (address[0]) palette[address[4:1]][11:8] <= write_data[3:0];
                    else palette[address[4:1]][7:0] <= write_data;
                end
                if (address >= 16'h4100 && address < 16'h4140)
                    sprites[address[5:0]] <= write_data;
                case (address)
                    16'h4020: video_enable <= write_data[0];
                    16'h4023: irq_enable <= write_data[0];
                    // A new frame event wins over acknowledgment in the same cycle.
                    16'h4024: if (write_data[0] && !vblank_start) irq_pending <= 0;
                    16'h4027: if (!irq_pending && !vblank_start) cpu_sleep <= write_data[0];
                    16'h403f: diagnostic <= write_data;
                    default: ;
                endcase
                if (address[15:4] == 12'h430) begin
                    case (address[2:0])
                        3'd0: tone_step[address[3]][7:0] <= write_data;
                        3'd1: tone_step[address[3]][15:8] <= write_data;
                        3'd2: tone_volume[address[3]] <= write_data[3:0];
                        3'd3: tone_gate[address[3]] <= write_data[0];
                        default: ;
                    endcase
                end
            end
        end
    end

    always @* begin
        read_data = 0;
        if (read_enable) begin
            if (address[15:12] == 4'h2)
                read_data = address[11] ? attributes[address[10:0]] : tiles[address[10:0]];
            if (address[15:5] == 11'h200)
                read_data = address[0] ? {4'd0,palette[address[4:1]][11:8]} : palette[address[4:1]][7:0];
            if (address >= 16'h4100 && address < 16'h4140) read_data = sprites[address[5:0]];
            case (address)
                16'h4020: read_data = {7'd0,video_enable};
                16'h4021: read_data = v[7:0];
                16'h4022: read_data = {7'd0,v[8]};
                16'h4023: read_data = {7'd0,irq_enable};
                16'h4024: read_data = {7'd0,irq_pending};
                16'h4025: read_data = frame_count[7:0];
                16'h4026: read_data = frame_count[15:8];
                16'h4027: read_data = {7'd0,cpu_sleep};
                16'h4030: read_data = latched_buttons;
                16'h403f: read_data = diagnostic;
                default: ;
            endcase
            if (address >= 16'h4040 && address < 16'h4048) begin
                case (address[1:0])
                    2'd0: read_data = {7'd0,timer_running[address[2]]};
                    2'd1: read_data = timer_ms[address[2]][7:0];
                    2'd2: read_data = timer_snapshot[address[2]][7:0];
                    2'd3: read_data = timer_snapshot[address[2]][15:8];
                endcase
            end
            if (address[15:4] == 12'h430) begin
                case (address[2:0])
                    3'd0: read_data = tone_step[address[3]][7:0];
                    3'd1: read_data = tone_step[address[3]][15:8];
                    3'd2: read_data = {4'd0,tone_volume[address[3]]};
                    3'd3: read_data = {7'd0,tone_gate[address[3]]};
                    default: read_data = 0;
                endcase
            end
        end
    end

    // Eight sprites, 16x16 pixels, two-bit masks. No CPU pixel loop.
    // Low slot numbers take priority. Mask 0=transparent, 1=shadow, 2=body, 3=light.
    function automatic [4:0] sprite_sample(input [8:0] px, py);
        integer slot, lx, ly, row;
        reg [1:0] ink;
        begin
            sprite_sample = 0;
            for (slot=7; slot>=0; slot=slot-1) begin
                if (sprites[slot*8+5][0]) begin
                lx = int'(px) - int'({sprites[slot*8+1][0],sprites[slot*8]});
                ly = int'(py) - int'(sprites[slot*8+2]);
                if (lx>=0 && lx<16 && ly>=0 && ly<16) begin
                    if (sprites[slot*8+5][1]) lx = 15-lx;
                    if (sprites[slot*8+5][2]) ly = 15-ly;
                    row = int'(sprites[slot*8+3][2:0])*16 + ly;
                    ink = 2'(sprite_rom[row] >> (lx*2));
                    case (ink)
                        2'd1: sprite_sample = {1'b1,4'd1};
                        2'd2: sprite_sample = {1'b1,sprites[slot*8+4][3:0]};
                        2'd3: sprite_sample = {1'b1,4'd15};
                        default: ;
                    endcase
                end
                end
            end
        end
    endfunction

    wire [10:0] tile_address = {5'd0,v[8:3]} * 11'd40 + {5'd0,h[8:3]};
    reg [8:0] x1=0, y1=0, x2=0, y2=0;
    reg [7:0] tile1=0, attr1=0, attr2=0, glyph2=0;
    reg [4:0] sprite2=0;
    reg de1=0, de2=0, hs1=1, hs2=1, vs1=1, vs2=1, enabled1=0, enabled2=0;
    always @(posedge clk) begin
        x1 <= h; y1 <= v; x2 <= x1; y2 <= y1;
        tile1 <= tiles[tile_address]; attr1 <= attributes[tile_address];
        glyph2 <= font_rom[{tile1,y1[2:0]}]; attr2 <= attr1;
        if (enabled1 && x1<9'd320 && y1<9'd204) sprite2 <= sprite_sample(x1,y1);
        else sprite2 <= 0;
        de1 <= h < 9'd320 && v < 9'd204; de2 <= de1;
        hs1 <= !(h >= 9'd344 && h < 9'd376); hs2 <= hs1;
        vs1 <= !(v >= 9'd220 && v < 9'd224); vs2 <= vs1;
        enabled1 <= video_enable; enabled2 <= enabled1;
        if (reset) begin
            x1<=0; y1<=0; x2<=0; y2<=0;
            de1<=0; de2<=0; enabled1<=0; enabled2<=0;
            hs1<=1; hs2<=1; vs1<=1; vs2<=1;
        end
    end
    wire [3:0] tile_color = glyph2[3'd7-x2[2:0]] ? attr2[7:4] : attr2[3:0];
    wire [3:0] color_index = sprite2[4] ? sprite2[3:0] : tile_color;
    wire [11:0] color = de2 && enabled2 ? palette[color_index] : 12'd0;
    assign red = {color[11:8],color[11:8]};
    assign green = {color[7:4],color[7:4]};
    assign blue = {color[3:0],color[3:0]};
    assign de = de2;
    assign hsync = hs2; assign vsync = vs2;
    assign video_x = x2; assign video_y = y2;

    wire [15:0] volume_l = {5'd0,tone_volume[0],7'd0};
    wire [15:0] volume_r = {5'd0,tone_volume[1],7'd0};
    assign audio_left = !reset && tone_gate[0] ? (tone_phase[0][23] ? volume_l : -volume_l) : 16'd0;
    assign audio_right = !reset && tone_gate[1] ? (tone_phase[1][23] ? volume_r : -volume_r) : 16'd0;
endmodule
