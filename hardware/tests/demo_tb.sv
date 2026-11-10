`timescale 1ns/1ps
module demo_tb;
    reg clk = 0;
    always #10 clk = ~clk; // Unit simulation counts clock edges; PLL is a separate target.
    reg reset = 1;
    reg [5:0] joystick = 0;
    reg continuous_tone = 0;
    reg grid = 0;
    wire ce_pixel, hsync, vsync, de;
    wire [7:0] red, green, blue;
    wire [15:0] audio_left, audio_right;
    wire [31:0] frame_count;
    wire [8:0] marker_x;
    wire [7:0] marker_y;
    chipbuilder_demo dut(.*);

    integer px = 0, py = 0, frames = 0, active_pixels = 0;
    integer tone_edges = 0, samples_since_edge = 0;
    reg old_tone = 0;
    reg [23:0] prior_pixel;
    reg [23:0] prior_line [0:639];
    integer preview;
    initial begin
        preview = $fopen("preview.ppm", "wb");
        if (preview == 0) $fatal(1, "preview output could not be opened");
        $fwrite(preview, "P6\n640 480\n255\n");
    end

    always @(negedge clk) begin
        if (audio_left !== audio_right) $fatal(1, "stereo mismatch");
        if (audio_left != 0 && audio_left != 16'h0400 && audio_left != 16'hfc00)
            $fatal(1, "invalid audio amplitude");
        if (ce_pixel) begin
            if (frames == 1 && de) $fwrite(preview, "%c%c%c", red, green, blue);
            if (de !== (px < 640 && py < 480)) $fatal(1, "display enable timing");
            if (hsync !== !(px >= 656 && px < 752)) $fatal(1, "HSYNC timing");
            if (vsync !== !(py >= 490 && py < 492)) $fatal(1, "VSYNC timing");
            if (px >= 640 || py < 36 || py >= 444) begin
                if ({red,green,blue} !== 24'd0) $fatal(1, "blanking/letterbox pixels");
            end else begin
                active_pixels = active_pixels + 1;
                if (px[0] && {red,green,blue} !== prior_pixel) $fatal(1, "horizontal 2x replication");
                if (py[0] && {red,green,blue} !== prior_line[px]) $fatal(1, "vertical 2x replication");
                if (px == (int'(marker_x)*2 + 4) && py == (36 + int'(marker_y)*2 + 4)) begin
                    if ({red,green,blue} !== (joystick[5] ? 24'h00ffff : 24'hff40ff))
                        $fatal(1, "marker position/color pixel");
                end
            end
            if (px < 640) prior_line[px] = {red,green,blue};
            prior_pixel = {red,green,blue};
            if (px == 799) begin
                px = 0;
                if (py == 524) begin
                    py = 0;
                    frames = frames + 1;
                    if (frames == 2) $fclose(preview);
                    if (active_pixels != 640*408) $fatal(1, "image extent");
                    active_pixels = 0;
                end else py = py + 1;
            end else px = px + 1;
        end
        if (reset) begin
            samples_since_edge = 0;
            tone_edges = 0;
            old_tone = 0;
            if (audio_left !== 0) $fatal(1, "reset must mute audio");
        end else begin
            samples_since_edge = samples_since_edge + 1;
            if (dut.tone_high != old_tone) begin
                if (tone_edges > 0 && (samples_since_edge < 57272 || samples_since_edge > 57273))
                    $fatal(1, "440Hz divider edge interval %0d", samples_since_edge);
                samples_since_edge = 0;
                tone_edges = tone_edges + 1;
                old_tone = dut.tone_high;
            end
        end
    end

    task next_frame;
        integer target;
        begin
            target = frames + 1;
            wait(frames == target);
            @(negedge clk);
        end
    endtask

    initial begin
        // Leave reset on until a frame boundary so expected movements are explicit.
        next_frame();
        reset = 0;
        joystick = 6'b010101; // right, down, A
        next_frame();
        if (marker_x != 153 || marker_y != 95 || frame_count != 1)
            $fatal(1, "frame-latched controller movement");
        if (audio_left == 0 || tone_edges < 14) $fatal(1, "button tone missing");
        joystick = 6'b001010; // left/up, muted
        next_frame();
        if (marker_x != 152 || marker_y != 94 || frame_count != 2)
            $fatal(1, "reverse controller movement");
        if (audio_left != 0) $fatal(1, "tone should mute on release");
        joystick = 6'b001111; // opposing directions cancel
        grid = 1;
        continuous_tone = 1;
        next_frame();
        if (marker_x != 152 || marker_y != 94 || audio_left == 0)
            $fatal(1, "opposing directions or continuous tone");
        joystick = 6'b100000;
        next_frame(); // Pixel assertions check B's alternate marker color.
        // User reset changes state and sound while raster counters keep running.
        reset = 1;
        repeat (6) @(negedge clk);
        if (marker_x != 152 || marker_y != 94 || frame_count != 0 || audio_left != 0)
            $fatal(1, "reset state");
        reset = 0;
        joystick = 6'b010101;
        // Inject boundary state for fast directed clamp checks. +long additionally
        // reaches those boundaries solely through 310 frames of held input.
        if ($test$plusargs("long")) repeat (310) next_frame();
        else begin
            dut.marker_x = 9'd304;
            dut.marker_y = 8'd188;
            next_frame();
        end
        if (marker_x != 304 || marker_y != 188) $fatal(1, "right/down clamp");
        joystick = 6'b001010;
        if ($test$plusargs("long")) repeat (310) next_frame();
        else begin
            dut.marker_x = 0;
            dut.marker_y = 0;
            next_frame();
        end
        if (marker_x != 0 || marker_y != 0) $fatal(1, "left/up clamp");
        $display("PASS: raster timing, 2x pixels, frame counter, controls, clamps, reset and audio");
        $finish;
    end
    initial begin
        #12000000000;
        $fatal(1, "simulation timeout");
    end
endmodule
