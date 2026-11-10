// SPDX-License-Identifier: GPL-2.0-or-later
#include "Vcore.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

class Machine {
public:
    VerilatedContext context;
    Vcore cpu{&context};
    std::array<uint8_t,65536> memory{};
    uint64_t cycles = 0;
    Machine() { cpu.irq_n_i=cpu.nmi_n_i=cpu.so_n_i=cpu.rdy_i=1; }
    void tick() {
        cpu.clk_clk_i=0; cpu.eval();
        if (cpu.wr_o && cpu.rst_rst_n_i) memory[cpu.a_o]=cpu.d_o;
        cpu.d_i=memory[cpu.a_o]; cpu.eval();
        cpu.clk_clk_i=1; cpu.eval();
        ++cycles;
    }
    void reset(uint16_t vector) {
        memory[0xfffc]=uint8_t(vector); memory[0xfffd]=uint8_t(vector>>8);
        cpu.rst_rst_n_i=0;
        for (int i=0;i<10;++i) tick();
        cpu.rst_rst_n_i=1;
        cycles=0;
    }
    void load(const std::string& name) {
        std::ifstream file(name,std::ios::binary);
        require(bool(file),"Cannot open test ROM: "+name);
        file.read(reinterpret_cast<char*>(memory.data()),memory.size());
        require(file.gcount()==65536,"Functional test ROM must contain exactly 64 KiB");
    }
};

static void directed() {
    Machine m;
    // Independent instruction-cycle expectations: LDA #, STA zp, LDX #, INX,
    // STX abs, BRA (taken, same page), JMP abs. The reset vector is actually read.
    const std::vector<uint8_t> program = {
        0xa9,0x12, 0x85,0x10, 0xa2,0x03, 0xe8, 0x8e,0x00,0x02,
        0x80,0x02, 0xea,0xea, 0x4c,0x0e,0x80
    };
    std::copy(program.begin(),program.end(),m.memory.begin()+0x8000);
    m.reset(0x8000);
    std::vector<std::pair<unsigned,uint64_t>> fetches;
    for (unsigned i=0;i<120;++i) {
        m.tick();
        if (m.cpu.sync_o) fetches.emplace_back(m.cpu.a_o,m.cycles);
    }
    const std::array<unsigned,7> addresses={0x8000,0x8002,0x8004,0x8006,0x8007,0x800a,0x800e};
    const std::array<unsigned,6> clocks={2,3,2,2,4,3};
    require(fetches.size()>=addresses.size(),"CPU did not fetch the directed program");
    for (unsigned i=0;i<addresses.size();++i) {
        require(fetches[i].first==addresses[i],"Reset/branch instruction address mismatch");
        if (i) require(fetches[i].second-fetches[i-1].second==clocks[i-1],
                       "Instruction bus-cycle count mismatch at index "+std::to_string(i));
    }
    require(m.memory[0x10]==0x12 && m.memory[0x200]==4,"Zero-page/absolute writes failed");

    // A minimal regression for the upstream BRK bug: stacked D must be retained,
    // while the handler's live D flag is clear. Check with CPU-executed reads.
    Machine b;
    const std::vector<uint8_t> main={0xf8,0x00,0xea,0x4c,0x03,0x80}; // SED; BRK; padding; loop
    const std::vector<uint8_t> handler={0xba,0xbd,0x01,0x01,0x85,0x20,0x08,0x68,0x85,0x21,0x4c,0x0a,0x90};
    std::copy(main.begin(),main.end(),b.memory.begin()+0x8000);
    std::copy(handler.begin(),handler.end(),b.memory.begin()+0x9000);
    b.memory[0xfffe]=0; b.memory[0xffff]=0x90;
    b.reset(0x8000);
    for (int i=0;i<150;++i) b.tick();
    require((b.memory[0x20]&0x18)==0x18,"BRK stack must preserve D and set B");
    require((b.memory[0x21]&0x0c)==0x04,"BRK handler must clear D and set I");
    std::cout<<"PASS: CPU reset vector, instruction addresses/cycles, RAM writes, BRK stacked/live flags\n";
}

static void functional(const std::string& file, unsigned success) {
    Machine m;
    m.load(file);
    m.reset(0x0400); // Standard suite entry; change reset vector, not the CPU PC.
    unsigned prior=0, repeats=0;
    const auto start=std::chrono::steady_clock::now();
    for (unsigned i=0;i<150000000;++i) {
        m.tick();
        if (m.cpu.sync_o) {
            repeats=m.cpu.a_o==prior ? repeats+1 : 0;
            prior=m.cpu.a_o;
            if (repeats>32) {
                if (prior!=success) {
                    std::cerr<<"Functional test trap at $"<<std::hex<<prior<<std::dec<<" after "<<m.cycles<<" clocks\n";
                    throw std::runtime_error("CPU functional test failed");
                }
                require(m.cycles>1000000,"Functional test reached success implausibly early");
                std::cout<<"PASS: "<<file<<" at $"<<std::hex<<success<<std::dec
                    <<" after "<<m.cycles<<" clocks ("
                    <<std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count()<<" seconds)\n";
                return;
            }
        }
    }
    throw std::runtime_error("CPU functional test timed out");
}

int main(int argc,char** argv) {
    try {
        if (argc==1) directed();
        else if (argc==4 && std::string(argv[1])=="--functional")
            functional(argv[2],std::stoul(argv[3],nullptr,16));
        else throw std::runtime_error("Usage: cpu-check [--functional ROM SUCCESS_HEX]");
        return 0;
    } catch (const std::exception& error) {
        std::cerr<<"FAIL: "<<error.what()<<"\n";
        return 1;
    }
}
