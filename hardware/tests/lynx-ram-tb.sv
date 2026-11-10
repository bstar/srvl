`timescale 1ns/1ps
// Compare the audit RAM against the actual Quartus altsyncram simulation model.
// Mixed-port read/write collisions and simultaneous writes to the same address
// are outside the upstream primitive's defined contract and are excluded.
module lynx_ram_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg ce_a = 1, ce_b = 1, we_a = 0, we_b = 0;
  reg [5:0] addr_a = 0, addr_b = 1;
  reg [7:0] data_a = 0, data_b = 0;
  wire [7:0] actual_a, actual_b, expected_a, expected_b;
  dpram actual (.clock_a(clk), .clock_b(clk), .clken_a(ce_a), .clken_b(ce_b),
    .address_a(addr_a), .address_b(addr_b), .data_a(data_a), .data_b(data_b),
    .wren_a(we_a), .wren_b(we_b), .q_a(actual_a), .q_b(actual_b));
  altsyncram #(
    .address_reg_b("CLOCK1"),
    .clock_enable_input_a("NORMAL"), .clock_enable_input_b("NORMAL"),
    .clock_enable_output_a("BYPASS"), .clock_enable_output_b("BYPASS"),
    .indata_reg_b("CLOCK1"), .intended_device_family("Cyclone V"),
    .lpm_type("altsyncram"), .numwords_a(64), .numwords_b(64),
    .operation_mode("BIDIR_DUAL_PORT"),
    .outdata_aclr_a("NONE"), .outdata_aclr_b("NONE"),
    .outdata_reg_a("UNREGISTERED"), .outdata_reg_b("UNREGISTERED"),
    .power_up_uninitialized("FALSE"),
    .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
    .read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
    .widthad_a(6), .widthad_b(6), .width_a(8), .width_b(8),
    .width_byteena_a(1), .width_byteena_b(1),
    .wrcontrol_wraddress_reg_b("CLOCK1")
  ) expected (.clock0(clk), .clock1(clk), .clocken0(ce_a), .clocken1(ce_b),
    .address_a(addr_a), .address_b(addr_b), .data_a(data_a), .data_b(data_b),
    .wren_a(we_a), .wren_b(we_b), .q_a(expected_a), .q_b(expected_b),
    .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0), .addressstall_b(1'b0),
    .byteena_a(1'b1), .byteena_b(1'b1), .clocken2(1'b1), .clocken3(1'b1),
    .rden_a(1'b1), .rden_b(1'b1));

  reg [31:0] rng = 32'h5a17c93e;
  reg valid_a = 0, valid_b = 0;
  integer checks = 0, i;
  initial begin
    for (i = 0; i < 12000; i = i + 1) begin
      @(negedge clk);
      rng = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
      addr_a = rng[5:0]; addr_b = rng[13:8];
      data_a = rng[23:16]; data_b = rng[31:24];
      ce_a = rng[6]; ce_b = rng[14];
      we_a = rng[7]; we_b = rng[15];
      if (addr_a == addr_b && we_a && ce_a && we_b && ce_b) we_b = 0;
      @(posedge clk);
      if (ce_a) valid_a = !(ce_b && we_b && addr_a == addr_b);
      if (ce_b) valid_b = !(ce_a && we_a && addr_a == addr_b);
      #1;
      if (valid_a) begin
        if (actual_a !== expected_a) $fatal(1, "port A mismatch at cycle %0d: %02x != %02x", i, actual_a, expected_a);
        checks = checks + 1;
      end
      if (valid_b) begin
        if (actual_b !== expected_b) $fatal(1, "port B mismatch at cycle %0d: %02x != %02x", i, actual_b, expected_b);
        checks = checks + 1;
      end
    end
    $display("PASS: audit RAM matches Quartus altsyncram for %0d defined port observations across 12000 cycles", checks);
    $finish;
  end
endmodule
