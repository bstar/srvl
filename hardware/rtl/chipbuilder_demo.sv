// SPDX-License-Identifier: GPL-2.0-or-later
// Prototype display/input/audio circuit; not the final console graphics engine.
`timescale 1ns/1ps
module chipbuilder_demo (
    input wire clk,                    // 50.4 MHz
    input wire reset,
    input wire [5:0] joystick,          // Right, Left, Down, Up, A, B
    input wire continuous_tone,
    input wire grid,
    output wire ce_pixel,              // 25.2 MHz: 800 * 525 * 60
    output reg [7:0] red, green, blue,
    output wire hsync, vsync, de,
    output wire [15:0] audio_left, audio_right,
    output reg [31:0] frame_count = 0,
    output reg [8:0] marker_x = 9'd152,
    output reg [7:0] marker_y = 8'd94
);
    reg pixel_phase = 0;
    reg [9:0] h = 0;
    reg [9:0] v = 0;
    wire frame_end = pixel_phase && h == 10'd799 && v == 10'd524;
    assign ce_pixel = pixel_phase;
    // Standard 640x480 raster with 36 black lines above/below the 640x408 image.
    // Signals remain running during user reset so the display retains sync.
    assign hsync = !(h >= 10'd656 && h < 10'd752);
    assign vsync = !(v >= 10'd490 && v < 10'd492);
    assign de = h < 10'd640 && v < 10'd480;

    always @(posedge clk) begin
        pixel_phase <= ~pixel_phase;
        if (pixel_phase) begin
            if (h == 10'd799) begin
                h <= 0;
                if (v == 10'd524) v <= 0;
                else v <= v + 10'd1;
            end else h <= h + 10'd1;
        end
        if (reset) begin
            frame_count <= 0;
            marker_x <= 9'd152;
            marker_y <= 8'd94;
        end else if (frame_end) begin
            frame_count <= frame_count + 32'd1;
            if (joystick[0] && !joystick[1] && marker_x < 9'd304)
                marker_x <= marker_x + 9'd1;
            if (joystick[1] && !joystick[0] && marker_x > 0)
                marker_x <= marker_x - 9'd1;
            if (joystick[2] && !joystick[3] && marker_y < 8'd188)
                marker_y <= marker_y + 8'd1;
            if (joystick[3] && !joystick[2] && marker_y > 0)
                marker_y <= marker_y - 8'd1;
        end
    end

    wire image_area = de && v >= 10'd36 && v < 10'd444;
    wire [8:0] x = h[9:1];
    wire [9:0] image_v = v - 10'd36;
    wire [7:0] y = image_v[8:1];
    wire marker = x >= marker_x && x < marker_x + 9'd16 &&
                  {1'b0,y} >= {1'b0,marker_y} &&
                  {1'b0,y} < {1'b0,marker_y} + 9'd16;
    // Avoid divide hardware for the per-frame counter strip: 32 blocks, 8 px wide.
    wire [4:0] frame_bit = x[7:3];
    always @* begin
        red = 0; green = 0; blue = 0;
        if (image_area) begin
            // Eight 40-pixel-wide RGB bars; every logical pixel is repeated 2x2.
            if      (x < 9'd40)  begin red=255; green=255; blue=255; end
            else if (x < 9'd80)  begin red=255; green=255; blue=0;   end
            else if (x < 9'd120) begin red=0;   green=255; blue=255; end
            else if (x < 9'd160) begin red=0;   green=255; blue=0;   end
            else if (x < 9'd200) begin red=255; green=0;   blue=255; end
            else if (x < 9'd240) begin red=255; green=0;   blue=0;   end
            else if (x < 9'd280) begin red=0;   green=0;   blue=255; end
            else                begin red=32;  green=32;  blue=32;  end
            if (y >= 8'd150) begin
                red = x[0] ^ y[0] ? 8'd255 : 8'd0;
                green = red; blue = red;
            end
            if (grid && (x[3:0] == 0 || y[3:0] == 0)) begin
                red=0; green=0; blue=0;
            end
            if (y < 8'd4 && x < 9'd256) begin
                red=0; green=frame_count[frame_bit] ? 8'd255 : 8'd32; blue=0;
            end
            if (marker) begin
                red=joystick[5] ? 8'd0 : 8'd255;
                green=joystick[5] ? 8'd255 : 8'd64;
                blue=8'd255;
            end
            if (x == 0 || x == 9'd319 || y == 0 || y == 8'd203) begin
                red=255; green=255; blue=255;
            end
        end
    end

    // Fractional divider: precisely 440 complete square-wave periods per second
    // at the specified 50.4 MHz clock, with at most one clock of edge quantization.
    reg [25:0] tone_phase = 0;
    reg tone_high = 0;
    always @(posedge clk) begin
        if (reset) begin
            tone_phase <= 0;
            tone_high <= 0;
        end else if (tone_phase >= 26'd50399120) begin
            tone_phase <= tone_phase - 26'd50399120;
            tone_high <= ~tone_high;
        end else tone_phase <= tone_phase + 26'd880;
    end
    wire tone_enabled = !reset && (joystick[4] || continuous_tone);
    assign audio_left = tone_enabled ? (tone_high ? 16'h0400 : 16'hfc00) : 16'h0000;
    assign audio_right = audio_left;
endmodule
