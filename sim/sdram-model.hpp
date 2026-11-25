// Independent command-level model for the Tang's 2M x32 SDR memory.
// Not vendor RTL and not an electrical/setup/hold or analog retention model.
// Timing checks are expressed in SDRAM clock edges, not controller FSM states.
#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <stdexcept>
#include <string>
#include <vector>

struct SdramPins {
  bool cke, cs_n, ras_n, cas_n, we_n, dq_oe;
  uint16_t address;
  uint8_t bank, dqm;
  uint32_t data;
};

class SdramModel {
  struct Bank {
    bool open = false;
    uint16_t row = 0;
    uint64_t activated = 0, available = 0;
  };
  struct Read { uint64_t due; uint32_t word; };
  std::array<Bank,4> banks{};
  std::deque<Read> reads;
  std::array<uint8_t,2> dqm_history{15,15};
  uint64_t blocked_until = 0, power_started = 0, last_refresh = 0;
  unsigned init_step = 0;
  bool read_driving = false;
  uint32_t bus = 0;
  void require(bool condition, const std::string &message) const {
    if (!condition) throw std::runtime_error("SDRAM edge " + std::to_string(cycles) + ": " + message);
  }
  bool closed() const {
    return std::all_of(banks.begin(),banks.end(),[&](const Bank &b) {
      return !b.open && cycles >= b.available;
    });
  }
public:
  // Conservative 64 MHz engineering checks: tRCD=2, tRP=2, write recovery=2,
  // refresh recovery=5, mode recovery=2; maximum refresh gap <15.625 us.
  // Board geometry/CAS are documented; these checks are not vendor signoff.
  uint64_t cycles = 0, activations = 0, read_count = 0, write_count = 0;
  uint64_t refresh_count = 0, max_refresh_gap = 0;
  uint64_t cartridge_read_count = 0;
  std::vector<uint32_t> memory;
  explicit SdramModel(): memory(2*1024*1024) {
    for (uint32_t i=0;i<memory.size();++i) memory[i]=0xa5c30000u ^ (i*0x9e3779b9u);
  }
  uint32_t dq() const { return read_driving ? bus : 0xdead0000u ^ uint32_t(cycles); }
  void expect_initialization() {
    init_step = 0; power_started = cycles;
    // Retain stored data and outstanding physical operations across a logic
    // reset. The subsequent PRECHARGE ALL must establish a known bank state.
  }
  void edge(const SdramPins &p) {
    ++cycles;
    read_driving = false;
    if (!reads.empty() && reads.front().due == cycles) {
      bus = reads.front().word;
      const uint8_t mask = dqm_history[0];
      for(unsigned lane=0;lane<4;++lane)
        if(mask & (1u<<lane)) bus ^= 0x69u<<(lane*8);
      read_driving = true; reads.pop_front();
    }
    dqm_history={dqm_history[1],p.dqm};
    require(!(read_driving && p.dq_oe),"FPGA and SDRAM both drive DQ");
    if(init_step==4) {
      const uint64_t gap=cycles-last_refresh;
      max_refresh_gap=std::max(max_refresh_gap,gap);
      require(gap<=1000,"refresh deadline missed under client load");
    }
    if(!p.cke || p.cs_n) return;
    const unsigned command=(unsigned(p.ras_n)<<2)|(unsigned(p.cas_n)<<1)|p.we_n;
    if(command==7) return;
    require(cycles>=blocked_until,"command during refresh/mode recovery");
    if(command==2) {
      require((p.address & 0x400)!=0,"initialization did not precharge all banks");
      if(init_step==0) require(cycles-power_started>=12800,"power-up wait shorter than 200 us at 64 MHz");
      for(auto &b:banks) { b.open=false; b.available=cycles+2; }
      blocked_until=cycles+2;
      if(init_step==0) init_step=1;
      return;
    }
    if(command==1) {
      require(closed(),"refresh before all banks finish precharge");
      require(init_step>=1,"refresh before initialization precharge");
      if(init_step==1 || init_step==2) ++init_step;
      last_refresh=cycles; ++refresh_count; blocked_until=cycles+5;
      return;
    }
    if(command==0) {
      require(init_step==3,"mode register before two initialization refreshes");
      require(closed(),"mode register with an active bank");
      require(p.bank==0 && p.address==0x020,"expected sequential burst-one / CAS-two mode");
      init_step=4; blocked_until=cycles+2; return;
    }
    require(init_step==4,"read/write/activate before complete initialization");
    Bank &bank=banks.at(p.bank);
    if(command==3) {
      require(!bank.open && cycles>=bank.available,"ACTIVATE before precharge/recovery completes");
      bank.open=true; bank.row=p.address; bank.activated=cycles; ++activations; return;
    }
    require(command==4 || command==5,"unsupported SDRAM command");
    require(bank.open,"READ/WRITE without an open row");
    require(cycles-bank.activated>=2,"tRCD violation");
    require((p.address & 0x700)==0x400,"expected auto-precharge and 8-bit column");
    const uint32_t word=(uint32_t(p.bank)<<19)|(uint32_t(bank.row)<<8)|(p.address & 255);
    if(command==4) {
      require(p.dq_oe,"write data not driven at WRITE command");
      for(unsigned lane=0;lane<4;++lane) if(!(p.dqm & (1u<<lane))) {
        const uint32_t mask=0xffu<<(8*lane);
        memory[word]=(memory[word]&~mask)|(p.data&mask);
      }
      ++write_count;
      bank.available=std::max(bank.activated+3,cycles+2)+2;
    } else {
      require(!p.dq_oe,"FPGA drives DQ on READ");
      if(word<0x100000/4) ++cartridge_read_count;
      reads.push_back({cycles+2,memory[word]}); ++read_count;
      bank.available=std::max(bank.activated+3,cycles+1)+2;
    }
    bank.open=false;
  }
};
