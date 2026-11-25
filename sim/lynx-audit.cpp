// Original bounded integration test; does not establish game compatibility.
#include "Vlynx_audit.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  if (argc != 2) throw std::runtime_error("expected diagnostic binary");
  std::ifstream input(argv[1], std::ios::binary);
  if (!input) throw std::runtime_error("cannot open diagnostic");
  std::vector<uint8_t> code{std::istreambuf_iterator<char>(input), {}};
  if (code.size() & 1) code.push_back(0xea);
  // BS93 header fields use big-endian addresses/sizes, unlike the word loader.
  std::vector<uint8_t> image{0x80, 0x08, 0x02, 0x00,
      uint8_t(code.size() >> 8), uint8_t(code.size()), 'B', 'S', '9', '3'};
  image.insert(image.end(), code.begin(), code.end());
  if (image.size() & 1) image.push_back(0xea);
  Vlynx_audit core;
  core.reset_in = 1;
  core.comm_rx = 1;
  core.romsize = image.size();
  core.rom_byte = 0xff;
  core.rom_ack = 0;
  core.romwrite_wren = 0;
  core.bios_wr = 0;
  core.JoyUP = core.JoyDown = core.JoyLeft = core.JoyRight = 0;
  core.KeyA = core.KeyB = core.KeyPause = core.Option1 = core.Option2 = 0;
  auto tick = [&]() {
    core.clk = 0; core.eval();
    core.clk = 1; core.eval();
  };
  for (int n = 0; n < 128; ++n) tick();
  for (unsigned n = 0; n < image.size(); n += 2) {
    core.romwrite_addr = n;
    core.romwrite_data = image[n] | (image[n+1] << 8);
    core.romwrite_wren = 1;
    tick();
    core.romwrite_wren = 0;
    for (int j = 0; j < 15; ++j) tick();
  }
  for (int n = 0; n < 128; ++n) tick();
  core.reset_in = 0;
  std::array<uint16_t, 16320> frame{};
  std::array<bool, 16320> seen{};
  auto run = [&](bool pressed, uint16_t expected) {
    core.KeyA = pressed;
    seen.fill(false);
    unsigned count = 0;
    for (unsigned cycle = 0; cycle < 8000000; ++cycle) {
      // No cartridge fetch is needed for a RAM executable, but service any
      // speculative reads with a bounded one-cycle response.
      core.rom_ack = core.rom_req;
      tick();
      if (core.pixel_out_we && core.pixel_out_addr < frame.size()) {
        const unsigned address = core.pixel_out_addr;
        frame[address] = core.pixel_out_data;
        if (frame[address] == expected && !seen[address]) {
          seen[address] = true;
          ++count;
        }
        if (count == frame.size()) {
          std::cout << "PASS: " << (pressed ? "A held" : "idle")
                    << ", all 16320 pixels RGB444=0x" << std::hex
                    << expected << std::dec << " after " << cycle+1
                    << " master cycles\n";
          return;
        }
      }
    }
    throw std::runtime_error("diagnostic did not produce the expected full frame; pixels="
                             + std::to_string(count));
  };
  run(false, 0x0f0);
  run(true, 0xf00);
  run(false, 0x0f0);
  // Reload while retaining the same FPGA instance/RAM, as a real launcher must.
  // This catches pending bus strobes that survive warm reset and steal the first
  // opcode fetch. The entire console is never reconstructed between boots.
  core.reset_in = 1;
  for (int n = 0; n < 128; ++n) tick();
  for (unsigned n = 0; n < image.size(); n += 2) {
    core.romwrite_addr = n;
    core.romwrite_data = image[n] | (image[n+1] << 8);
    core.romwrite_wren = 1; tick(); core.romwrite_wren = 0;
    for (int j = 0; j < 15; ++j) tick();
  }
  for (int n = 0; n < 128; ++n) tick();
  core.reset_in = 0;
  run(false, 0x0f0);
  core.final();
  std::cout << "PASS: translated Lynx CPU/RAM, Suzy multiply, Mikey timers/display and input diagnostic\n";
}
