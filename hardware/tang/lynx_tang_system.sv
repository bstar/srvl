// Portable system integration. Optional buffered video uses an independent
// pixel clock; board PLLs, pin buffers, serializers and analog audio are separate.
module lynx_tang_system #(parameter integer VIDEO=0, AUDIO=0) (
    input wire clk, reset, uart_rx,
    input wire video_clk, video_reset,
    output wire [11:0] video_rgb,
    output wire video_de, video_hsync, video_vsync, video_frame_valid,
    output wire [9:0] video_x, video_y,
    output wire [15:0] video_underruns,
    output wire uart_tx,
    output wire [31:0] status,
    output wire running,
    output wire [13:0] pixel_address,
    output wire [11:0] pixel_data,
    output wire pixel_write,
    output wire [15:0] audio_left, audio_right,
    input wire audio_clk, audio_reset,
    output wire audio_bclk, audio_ws, audio_sd, audio_started, audio_underrun,
    output wire [15:0] audio_underruns,
    output wire audio_frame_strobe, audio_frame_valid, audio_snapshot_valid,
    output wire [15:0] audio_snapshot_left, audio_snapshot_right,
    output wire comlynx_tx,
    output wire cart_request, cart_ack,
    output wire [19:0] cart_address,
    output wire [7:0] cart_byte,
    output wire [10:0] sdram_a,
    output wire [1:0] sdram_ba,
    output wire [3:0] sdram_dqm,
    output wire sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n,
    input wire [31:0] dq_in,
    output wire [31:0] dq_out,
    output wire dq_oe
);
    wire [7:0] rx_data, tx_data, command;
    wire rx_valid, rx_error, tx_valid, tx_ready, command_valid, command_done, command_error, protocol_error;
    wire [23:0] command_address;
    wire [15:0] command_data;
    lynx_uart uart (.clk(clk),.reset(reset),.rx(uart_rx),.tx(uart_tx),
        .rx_data(rx_data),.rx_valid(rx_valid),.framing_error(rx_error),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready));
    lynx_packet packet (.clk(clk),.reset(reset),.rx_data(rx_data),.rx_valid(rx_valid),.rx_error(rx_error),
        .command_valid(command_valid),.command(command),.address(command_address),.data(command_data),
        .command_done(command_done),.command_error(command_error),.status(status),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),.protocol_error(protocol_error));
    wire memory_initialized, bridge_fault;
    wire [6:0] presentation_status;
    wire [4:0] video_status;
    wire audio_ready_sync, audio_underrun_sync;
    assign presentation_status={audio_underrun_sync,audio_ready_sync,video_status};
    wire load_request, load_ready, load_response;
    wire [22:0] load_address;
    wire [31:0] load_data;
    wire [3:0] load_mask;
    wire [8:0] buttons, bios_address;
    wire [7:0] bios_data;
    wire bios_write, rom_write;
    wire [19:0] romsize, rom_address;
    wire [15:0] rom_data;
    wire unused_loading, unused_bios_valid, unused_image_valid;
    wire [20:0] unused_image_bytes;
    lynx_loader loader (.clk(clk),.reset(reset),.command_valid(command_valid),.command(command),
        .address(command_address),.data(command_data),.command_done(command_done),.command_error(command_error),
        .memory_initialized(memory_initialized),.protocol_error(protocol_error),
        .presentation_status(presentation_status),.status(status),.running(running),
        .loading(unused_loading),.bios_valid(unused_bios_valid),.image_valid(unused_image_valid),
        .buttons(buttons),.romsize(romsize),.image_bytes(unused_image_bytes),
        .memory_request(load_request),.memory_ready(load_ready),.memory_response(load_response),
        .memory_address(load_address),.memory_data(load_data),.memory_mask(load_mask),
        .bios_address(bios_address),.bios_data(bios_data),.bios_write(bios_write),
        .rom_address(rom_address),.rom_data(rom_data),.rom_write(rom_write));
    wire memory_request, memory_ready, memory_response, memory_write;
    wire [22:0] memory_address;
    wire [31:0] memory_data, memory_read_data;
    wire [3:0] memory_mask;
    wire bridge_request, bridge_ready, bridge_response, bridge_write;
    wire [22:0] bridge_address;
    wire [31:0] bridge_data;
    wire [3:0] bridge_mask;
    lynx_cart_bridge bridge (.clk(clk),.reset(reset),.running(running),
        .load_request(load_request),.load_ready(load_ready),.load_response(load_response),
        .load_address(load_address),.load_data(load_data),.load_mask(load_mask),
        .cart_request(cart_request),.cart_address(cart_address),.cart_ack(cart_ack),.cart_byte(cart_byte),
        .protocol_fault(bridge_fault),.memory_request(bridge_request),.memory_ready(bridge_ready),
        .memory_response(bridge_response),.memory_read_data(memory_read_data),.memory_write(bridge_write),
        .memory_address(bridge_address),.memory_data(bridge_data),.memory_mask(bridge_mask));
    generate if(VIDEO!=0) begin: buffered_video
        wire capture_valid, capture_ready, capture_response, capture_overflow, capture_fault;
        wire scan_valid, scan_ready, scan_response, scan_fault, scan_underrun, arbiter_fault;
        wire present, display_valid, frame_ready;
        wire [1:0] display_bank;
        wire [22:0] capture_address, scan_address;
        wire [31:0] capture_data, client_read_data;
        wire [3:0] capture_mask;
        wire [15:0] dropped_frames;
        wire [2:0] clients_ready, clients_response;
        (* ASYNC_REG="TRUE" *) reg underrun_meta, underrun_sync;
        always @(posedge clk) begin
            if(reset) begin underrun_meta<=0; underrun_sync<=0; end
            else begin underrun_meta<=scan_underrun; underrun_sync<=underrun_meta; end
        end
        assign video_status={bridge_fault || arbiter_fault,capture_fault || scan_fault,
                                    underrun_sync,capture_overflow,display_valid};
        wire _unused_capture_status=^{frame_ready,dropped_frames,client_read_data};
        lynx_frame_capture capture (.clk(clk),.reset(reset),.enable(running),
            .pixel_write(pixel_write),.pixel_address(pixel_address),.pixel_data(pixel_data),.present(present),
            .display_valid(display_valid),.display_bank(display_bank),.frame_ready(frame_ready),
            .overflow(capture_overflow),.capture_error(capture_fault),.dropped_frames(dropped_frames),
            .write_valid(capture_valid),.write_ready(capture_ready),.write_response(capture_response),
            .write_address(capture_address),.write_data(capture_data),.write_mask(capture_mask));
        lynx_scanout scanout (.clk(clk),.reset(reset),.video_clk(video_clk),.video_reset(video_reset),
            .display_valid(display_valid),.display_bank(display_bank),.present(present),
            .read_valid(scan_valid),.read_ready(scan_ready),.read_response(scan_response),
            .read_address(scan_address),.read_data(memory_read_data),
            .video_rgb(video_rgb),.video_de(video_de),.video_hsync(video_hsync),.video_vsync(video_vsync),
            .video_x(video_x),.video_y(video_y),.video_frame_valid(video_frame_valid),
            .underrun(scan_underrun),.underrun_count(video_underruns),.protocol_fault(scan_fault));
        assign {scan_ready,capture_ready,bridge_ready}=clients_ready;
        assign {scan_response,capture_response,bridge_response}=clients_response;
        cb_memory_arbiter arbiter (.clk(clk),.reset(reset),
            .client_valid({scan_valid,capture_valid,bridge_request}),.client_ready(clients_ready),
            .client_write({1'b0,1'b1,bridge_write}),
            .client_address({scan_address,capture_address,bridge_address}),
            .client_data({32'b0,capture_data,bridge_data}),.client_mask({4'b0,capture_mask,bridge_mask}),
            .client_response(clients_response),.client_read_data(client_read_data),.protocol_fault(arbiter_fault),
            .memory_valid(memory_request),.memory_ready(memory_ready),.memory_write(memory_write),
            .memory_address(memory_address),.memory_data(memory_data),.memory_mask(memory_mask),
            .memory_response(memory_response),.memory_read_data(memory_read_data));
    end else begin: source_stream_only
        assign {memory_request,memory_write,memory_address,memory_data,memory_mask}=
               {bridge_request,bridge_write,bridge_address,bridge_data,bridge_mask};
        assign bridge_ready=memory_ready;
        assign bridge_response=memory_response;
        assign video_status={bridge_fault,4'b0};
        assign video_rgb=0;
        assign {video_de,video_hsync,video_vsync,video_frame_valid}=4'b0110;
        assign video_x=0;
        assign video_y=0;
        assign video_underruns=0;
        wire _unused_video_clock=video_clk ^ video_reset;
    end endgenerate
    generate if(AUDIO!=0) begin: stereo_output
        (* ASYNC_REG="TRUE" *) reg ready_meta, ready_sync, underrun_meta, underrun_sync;
        always @(posedge clk) begin
            if(reset) begin ready_meta<=0; ready_sync<=0; underrun_meta<=0; underrun_sync<=0; end
            else begin
                ready_meta<=audio_started; ready_sync<=ready_meta;
                underrun_meta<=audio_underrun; underrun_sync<=underrun_meta;
            end
        end
        assign audio_ready_sync=ready_sync;
        assign audio_underrun_sync=underrun_sync;
        wire [15:0] unused_filtered_left, unused_filtered_right;
        lynx_audio_output output_path (.clk(clk),.reset(reset),.enable(running),
            .input_left(audio_left),.input_right(audio_right),.audio_clk(audio_clk),.audio_reset(audio_reset),
            .bclk(audio_bclk),.ws(audio_ws),.sd(audio_sd),.started(audio_started),.underrun(audio_underrun),
            .underrun_count(audio_underruns),.frame_strobe(audio_frame_strobe),.frame_valid(audio_frame_valid),
            .snapshot_valid(audio_snapshot_valid),.snapshot_left(audio_snapshot_left),.snapshot_right(audio_snapshot_right),
            .filtered_left(unused_filtered_left),.filtered_right(unused_filtered_right));
    end else begin: no_audio_transport
        assign audio_ready_sync=0;
        assign audio_underrun_sync=0;
        assign {audio_bclk,audio_ws,audio_sd,audio_started,audio_underrun}=5'b01000;
        assign audio_underruns=0;
        assign {audio_frame_strobe,audio_frame_valid,audio_snapshot_valid}=0;
        assign audio_snapshot_left=0;
        assign audio_snapshot_right=0;
        wire _unused_audio_clock=audio_clk ^ audio_reset;
    end endgenerate
    lynx_sdram memory (.clk(clk),.reset(reset),.request(memory_request),.request_ready(memory_ready),
        .write(memory_write),.address(memory_address),.write_data(memory_data),.write_mask(memory_mask),
        .response(memory_response),.read_data(memory_read_data),.initialized(memory_initialized),
        .sdram_a(sdram_a),.sdram_ba(sdram_ba),.sdram_dqm(sdram_dqm),.sdram_cke(sdram_cke),.sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),.sdram_cas_n(sdram_cas_n),.sdram_we_n(sdram_we_n),
        .dq_in(dq_in),.dq_out(dq_out),.dq_oe(dq_oe));
    lynx_audit console (.clk(clk),.reset_in(reset || !running),
        .rom_addr(cart_address),.rom_byte(cart_byte),.rom_req(cart_request),.rom_ack(cart_ack),
        .romsize(romsize),.romwrite_data(rom_data),.romwrite_addr(rom_address),.romwrite_wren(rom_write),
        .bios_wraddr(bios_address),.bios_wrdata(bios_data),.bios_wr(bios_write),
        .pixel_out_addr(pixel_address),.pixel_out_data(pixel_data),.pixel_out_we(pixel_write),
        .audio_l(audio_left),.audio_r(audio_right),
        .JoyRight(buttons[0]),.JoyLeft(buttons[1]),.JoyDown(buttons[2]),.JoyUP(buttons[3]),
        .KeyA(buttons[4]),.KeyB(buttons[5]),.KeyPause(buttons[6]),.Option1(buttons[7]),.Option2(buttons[8]),
        .comm_rx(1'b1),.comm_tx(comlynx_tx));
endmodule
