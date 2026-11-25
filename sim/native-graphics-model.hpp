// Test infrastructure only. Direct byte-lane/pixel references and passive bus
// observation; no production rendering or CPU behavior is implemented here.
#pragma once
#include "Vnative_graphics_top.h"
#include "verilated.h"
#include "scaled-blitter-model.hpp"
#include "sdram-model.hpp"
#include <array>
#include <functional>
#include <fstream>
#include <optional>
#include <stdexcept>

inline void native_require(bool ok,const std::string &why) { if(!ok) throw std::runtime_error(why); }
using NativeDescriptor=std::array<uint8_t,36>;
inline NativeDescriptor native_descriptor(const BlitCommand &c) {
  NativeDescriptor d{};
  auto word=[&](unsigned n,unsigned value) { d.at(n)=uint8_t(value);d.at(n+1)=uint8_t(value>>8); };
  d[0]=uint8_t(unsigned(c.fill)|(unsigned(c.fill_covered)<<2)|(unsigned(c.bpp4)<<3)|(unsigned(c.flip_x)<<4)|(unsigned(c.flip_y)<<5)|(unsigned(c.transparent)<<6));
  d[1]=c.fill_index;d[2]=uint8_t(c.palette|(c.band<<4));word(3,c.tag);
  word(5,c.source);d[7]=uint8_t(c.source>>16);word(8,c.destination);d[10]=uint8_t(c.destination>>16);
  word(11,c.source_width);word(13,c.source_height);word(15,c.source_stride);word(17,c.destination_stride);
  word(19,unsigned(c.x)&4095);word(21,unsigned(c.y)&4095);word(23,c.width);word(25,c.height);
  word(27,c.clip_x0);word(29,c.clip_y0);word(31,c.clip_x1);word(33,c.clip_y1);return d;
}
inline NativeDescriptor native_byte(bool write,uint32_t address,uint8_t data,uint16_t tag) {
  NativeDescriptor d{};d[0]=write?2:3;d[3]=uint8_t(tag);d[4]=uint8_t(tag>>8);
  d[8]=uint8_t(address);d[9]=uint8_t(address>>8);d[10]=uint8_t(address>>16);d[35]=data;return d;
}
class NativeGraphicsMachine {
  bool peer_pending=false;
  uint32_t peer_expected=0;
  uint64_t peer_next=0,peer_sequence=0;
  unsigned cpu_half_period,cpu_phase;
  uint64_t halves=0;
public:
  Vnative_graphics_top dut;
  SdramModel memory;
  std::vector<uint32_t> golden=memory.memory;
  uint64_t cycles=0,cpu_edges=0,peer_reads=0;
  bool peer_load=true,allow_fault=false;
  std::function<void()> before_cpu_edge;
  explicit NativeGraphicsMachine(unsigned half_period=4,unsigned phase=0):cpu_half_period(half_period),cpu_phase(phase) {
    dut.clk=0;dut.cpu_clk=0;dut.reset=1;dut.memory_stall=0;dut.test_fault=0;
    dut.test_bus_write=0;dut.test_bus_address=0;dut.test_bus_data=0;dut.peer_valid=0;dut.peer_address=0;dut.dq_in=0;
    dut.eval();dut.clk=1;dut.cpu_clk=1;dut.eval();reset();
  }
  void tick() {
    dut.clk=0;dut.dq_in=memory.dq();
    if(!dut.reset) {
      dut.peer_valid=((peer_load && cycles>=peer_next) || dut.peer_valid) && !peer_pending;
      if(dut.peer_valid) dut.peer_address=0x300000+uint32_t(peer_sequence%32640)*4;
    }
    dut.eval();
    memory.edge({bool(dut.sdram_cke),bool(dut.sdram_cs_n),bool(dut.sdram_ras_n),bool(dut.sdram_cas_n),bool(dut.sdram_we_n),bool(dut.dq_oe),
                 uint16_t(dut.sdram_a),uint8_t(dut.sdram_ba),uint8_t(dut.sdram_dqm),uint32_t(dut.dq_out)});
    dut.dq_in=memory.dq();dut.eval();
    if(!dut.reset) {
      if(dut.peer_response) {
        native_require(peer_pending && dut.peer_read_data==peer_expected,"synthetic front-read response/data corrupted");
        peer_pending=false;++peer_reads;
      }
      if(dut.peer_valid && dut.peer_ready) {
        native_require(!peer_pending,"front read accepted twice");peer_pending=true;
        peer_expected=golden.at(dut.peer_address/4);peer_next+=32;++peer_sequence;
      }
    }
    for(unsigned half=0;half<2;++half) {
      const bool next_cpu=((halves+cpu_phase)/cpu_half_period)%2;
      if(next_cpu && !dut.cpu_clk) {
        if(!dut.reset && before_cpu_edge) before_cpu_edge();
        ++cpu_edges;
      }
      dut.cpu_clk=next_cpu;dut.eval();
      if(half==1) { dut.clk=1;dut.eval(); }
      ++halves;
    }
    ++cycles;
    native_require(allow_fault || !dut.protocol_fault,"native graphics memory/engine protocol fault");
  }
  void idle(uint64_t count) { while(count--) tick(); }
  void reset() {
    peer_pending=false;dut.peer_valid=0;dut.test_bus_write=0;dut.memory_stall=0;dut.test_fault=0;dut.reset=1;
    tick();memory.expect_initialization();idle(40);dut.reset=0;golden=memory.memory;
    peer_next=cycles;peer_sequence=0;
  }
  uint8_t read(unsigned offset) { dut.test_bus_address=uint8_t(offset);dut.eval();return dut.test_read_data; }
  uint32_t read32(unsigned offset) {
    uint32_t value=0;for(unsigned i=0;i<4;++i) value|=uint32_t(read(offset+i))<<(8*i);return value;
  }
  void write(unsigned offset,uint8_t data) {
    dut.test_bus_address=uint8_t(offset);dut.test_bus_data=data;dut.test_bus_write=1;
    const auto prior=cpu_edges;while(cpu_edges==prior) tick();
    dut.test_bus_write=0;dut.eval();
  }
  void stage(const NativeDescriptor &d) { for(unsigned i=0;i<d.size();++i) write(0x40+i,d[i]); }
  void wait_done() {
    const auto deadline=cycles+8000000;
    while(!(read(2)&4) && cycles<deadline) tick();
    native_require(cycles<deadline,"native command completion timeout");
  }
  void check_memory() { native_require(memory.memory==golden,"native command differs from full physical-memory reference"); }
  void preview(const std::string &path) const {
    std::ofstream out(path,std::ios::binary);out<<"P6\n320 204\n255\n";
    for(unsigned y=0;y<204;++y) for(unsigned x=0;x<320;++x) {
      const unsigned pixel=memory.memory.at((0x180000+y*640+x*2)/4)>>(16*(x%2));
      const unsigned index=pixel&255;
      const std::array<uint8_t,3> rgb=!(pixel&0x1000) ? std::array<uint8_t,3>{15,25,23}:
        !index ? std::array<uint8_t,3>{216,220,219}:
        std::array<uint8_t,3>{uint8_t(45+(index*37)%200),uint8_t(40+(index*67)%205),uint8_t(35+(index*97)%210)};
      out.write(reinterpret_cast<const char *>(rgb.data()),3);
    }
    native_require(bool(out),"native physical-memory preview failed");
  }
};
