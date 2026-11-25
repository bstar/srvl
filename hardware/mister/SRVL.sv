//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu (
    `include "sys/emu_ports.vh"
);

assign ADC_BUS = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = '0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE,
        SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS,
        SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN,
        DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;
assign VGA_SL = 2'b00;
assign VGA_F1 = 1'b0;
assign VGA_SCALER = 1'b0;
assign VGA_DISABLE = 1'b0;
assign HDMI_FREEZE = 1'b0;
assign HDMI_BLACKOUT = 1'b0;
assign HDMI_BOB_DEINT = 1'b0;
assign LED_DISK = 2'b00;
assign LED_POWER = 2'b00;
assign BUTTONS = 2'b00;
assign AUDIO_MIX = 2'b00;
assign AUDIO_S = 1'b1;
// 320:204 reduced to 80:51, displayed inside a 4:3 640x480 raster.
// The raster already contains the letterbox borders; keep its aspect 4:3.
assign VIDEO_ARX = 13'd4;
assign VIDEO_ARY = 13'd3;

`include "build_id.v"
localparam CONF_STR = {
    "SRVL;;",
    "O[1],Tone,Button A,Continuous;",
    "O[2],Test grid,Off,On;",
    "-;",
    "J1,Tone,Color;",
    "T[0],Reset;",
    "R[0],Reset and close OSD;",
    "v,0;",
    "V,v", `BUILD_DATE
};
wire clk_sys;
wire pll_locked;
wire [1:0] buttons;
wire [127:0] status;
wire [31:0] joystick;

// The instance name is part of sys_top.sdc's clock-group pattern. Preserve the
// template hierarchy so its asynchronous-domain constraints match this clock.
pll pll (
    .refclk(CLK_50M), .rst(1'b0),
    .outclk_0(clk_sys), .locked(pll_locked)
);

hps_io #(.CONF_STR(CONF_STR)) hps_io (
    .clk_sys(clk_sys), .HPS_BUS(HPS_BUS),
    .buttons(buttons), .status(status), .joystick_0(joystick),
    .status_in(128'd0), .status_set(1'b0), .status_menumask(16'd0),
    .info_req(1'b0), .info(8'd0),
    .video_rotated(1'b0), .new_vmode(1'b0),
    .joystick_0_rumble(16'd0), .joystick_1_rumble(16'd0),
    .joystick_2_rumble(16'd0), .joystick_3_rumble(16'd0),
    .joystick_4_rumble(16'd0), .joystick_5_rumble(16'd0)
);

// Synchronize reset release; raster timing continues through user resets.
reg [2:0] startup_reset = 3'b111;
always @(posedge clk_sys or negedge pll_locked) begin
    if (!pll_locked) startup_reset <= 3'b111;
    else startup_reset <= {startup_reset[1:0], 1'b0};
end
wire logic_reset = startup_reset[2] | RESET | status[0] | buttons[1];

assign CLK_VIDEO = clk_sys;
wire [31:0] frame_count;
wire [8:0] marker_x;
wire [7:0] marker_y;
srvl_demo demo (
    .clk(clk_sys), .reset(logic_reset),
    .joystick(joystick[5:0]),
    .continuous_tone(status[1]), .grid(status[2]),
    .ce_pixel(CE_PIXEL),
    .red(VGA_R), .green(VGA_G), .blue(VGA_B),
    .hsync(VGA_HS), .vsync(VGA_VS), .de(VGA_DE),
    .audio_left(AUDIO_L), .audio_right(AUDIO_R),
    .frame_count(frame_count), .marker_x(marker_x), .marker_y(marker_y)
);
assign LED_USER = frame_count[5];
endmodule
