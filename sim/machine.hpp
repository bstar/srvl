// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "Vsrvl_soc.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

class Console {
public:
    static constexpr unsigned width=320, height=204, clocks_per_frame=400*262;
    static constexpr unsigned clock_hz=clocks_per_frame*60;
    VerilatedContext context;
    Vsrvl_soc model{&context};
    std::array<uint32_t,width*height> pixels{};
    std::array<uint8_t,65536> writes{}; // Bus observation only, never feeds the CPU.
    std::vector<int16_t> audio;
    uint64_t clocks=0, opcode_fetches=0, bus_writes=0;
    unsigned audio_divider=0;

    Console() { reset(); }
    void tick() {
        model.clk=0; model.eval();
        if (model.trace_write) {
            writes[model.trace_address]=model.trace_data;
            ++bus_writes;
        }
        if (model.trace_sync) ++opcode_fetches;
        model.clk=1; model.eval();
        if (model.de && model.video_x<width && model.video_y<height)
            pixels[model.video_y*width+model.video_x]=0xff000000u | (uint32_t(model.red)<<16)
                | (uint32_t(model.green)<<8) | uint32_t(model.blue);
        if (++audio_divider==131) { // 6.288 MHz / 131 = 48 kHz, exactly 800 stereo samples/frame.
            audio_divider=0;
            audio.push_back(int16_t(model.audio_left));
            audio.push_back(int16_t(model.audio_right));
        }
        ++clocks;
    }
    void reset() {
        model.reset=1; model.buttons=0;
        for (int i=0;i<8;++i) tick();
        model.reset=0;
        pixels.fill(0xff000000u); writes.fill(0);
        audio.clear(); audio_divider=0;
    }
    void frame(uint8_t buttons=0) {
        audio.clear(); model.buttons=buttons;
        const auto old=model.frame_count;
        unsigned count=0;
        do {
            tick();
            if (++count>clocks_per_frame+8) throw std::runtime_error("Video frame timeout");
        } while(model.frame_count==old);
    }
    unsigned player_x() const { return writes[0x4100] | ((writes[0x4101]&1u)<<8); }
    unsigned player_y() const { return writes[0x4102]; }
    unsigned enemy_x(unsigned i=0) const { return writes[0x4110+i*8] | ((writes[0x4111+i*8]&1u)<<8); }
    unsigned enemy_y(unsigned i=0) const { return writes[0x4112+i*8]; }
    unsigned enemies() const { const auto n=writes[0x2000+10];return n>='2' && n<='5'?n-'0':0; }
    bool jammed() const { return writes[0x4114]==11; }
    unsigned score() const { return (model.diagnostic>>4)&3; }
    unsigned state() const { return model.diagnostic&3; }
    unsigned level() const { return writes[0x2000+4*40+31]-'1'; }
    void screenshot(const std::string& path) const {
        std::ofstream file(path,std::ios::binary);
        if (!file) throw std::runtime_error("Cannot write screenshot: "+path);
        file<<"P6\n"<<width<<" "<<height<<"\n255\n";
        for (auto pixel:pixels) {
            const char rgb[]={char(pixel>>16),char(pixel>>8),char(pixel)};
            file.write(rgb,3);
        }
    }
};
