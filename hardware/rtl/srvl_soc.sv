// SPDX-License-Identifier: GPL-2.0-or-later
// Software-first console prototype. This map is not the Lynx legacy memory map.
module srvl_soc #(
    parameter ROM_FILE = "courier.hex",
    parameter FONT_FILE = "font.hex",
    parameter SPRITE_FILE = "sprites.hex"
) (
    input wire clk, reset,
    input wire [7:0] buttons,
    output wire [7:0] red, green, blue,
    output wire de, hsync, vsync,
    output wire [8:0] video_x, video_y,
    output wire [15:0] audio_left, audio_right,
    output wire [15:0] frame_count,
    output wire [7:0] diagnostic,
    output wire [15:0] trace_address,
    output wire [7:0] trace_data,
    output wire trace_write, trace_sync
);
    reg [7:0] ram [0:8191];
    reg [7:0] rom [0:32767];
    initial $readmemh(ROM_FILE,rom);
    wire [15:0] address;
    wire [7:0] write_data;
    // In hierarchical simulation the CPU is a black box, so Verilator cannot
    // see that its address output is registered. The RAM->CPU->address path is
    // not a combinational feedback loop. Flat/hierarchical game tests compare it.
    /* verilator lint_off UNOPTFLAT */
    reg [7:0] read_data;
    /* verilator lint_on UNOPTFLAT */
    wire write_enable, read_enable, write_n, sync, irq, cpu_sleep;
    wire _unused_cpu_strobes = &{1'b0, write_n};
    // Stop the CPU between frame updates. Update the gate only while the master
    // clock is low; video/audio/input hardware continues running. A physical FPGA
    // adapter must map this function onto its dedicated clock-control resource.
    reg cpu_running = 1;
    always @(negedge clk) cpu_running <= reset || !cpu_sleep;
    wire cpu_clock = clk && cpu_running;
    wire [7:0] peripheral_data;
    // Only genuine CPU read cycles reach the peripherals: the timer's low-byte
    // snapshot must not fire on dummy cycles or while the CPU clock is stopped.
    wire peripheral_read = read_enable && cpu_running && !reset;
    wire peripheral_write = write_enable && cpu_running && !reset && address >= 16'h2000 && address < 16'h8000;
    srvl_cpu cpu (
        .clk(cpu_clock), .reset(reset), .read_data(read_data), .irq(irq),
        .address(address), .write_data(write_data), .write_enable(write_enable),
        .write_n(write_n), .read_enable(read_enable), .sync(sync)
    );
    always @(posedge clk) begin
        if (!reset && cpu_running && write_enable && address < 16'h2000)
            ram[address[12:0]] <= write_data;
    end
    // ROM writes and unmapped writes have no effect. Unmapped reads return zero.
    // Asynchronous read data remains valid even during the CPU's dummy bus cycles.
    always @* begin
        if (address[15]) read_data = rom[address[14:0]];
        else if (address < 16'h2000) read_data = ram[address[12:0]];
        else read_data = peripheral_data;
    end
    srvl_peripherals #(.FONT_FILE(FONT_FILE),.SPRITE_FILE(SPRITE_FILE)) peripherals (
        .clk(clk), .reset(reset), .address(address), .write_data(write_data),
        .write_enable(peripheral_write), .read_enable(peripheral_read), .read_data(peripheral_data),
        .buttons(buttons), .irq(irq), .cpu_sleep(cpu_sleep), .red(red), .green(green), .blue(blue),
        .de(de), .hsync(hsync), .vsync(vsync), .video_x(video_x), .video_y(video_y),
        .audio_left(audio_left), .audio_right(audio_right), .frame_count(frame_count),
        .diagnostic(diagnostic)
    );
    assign trace_address = address;
    assign trace_data = write_data;
    assign trace_write = write_enable && cpu_running && !reset;
    assign trace_sync = sync && cpu_running;
endmodule
