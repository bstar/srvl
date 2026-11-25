#include "native-graphics-model.hpp"
#include <fstream>
#include <iostream>
#include <random>

static uint64_t commands=0,draws=0,byte_ops=0,format_errors=0;
static void check_result(NativeGraphicsMachine &m,const NativeDescriptor &d,unsigned error,unsigned samples=0,unsigned pixels=0) {
  m.wait_done();++commands;
  native_require(m.read(5)==error,"MMIO completion error mismatch");
  native_require(m.read(6)==d[3] && m.read(7)==d[4],"MMIO completion tag replaced/torn");
  native_require(m.read32(0x10)==samples && m.read32(0x14)==pixels,"MMIO sample/pixel counters differ");
  const uint8_t status=m.read(2);
  native_require(!(status&3) && bool(status&8)==bool(error),"MMIO busy/ready/error status inconsistent");
  std::array<uint8_t,31> snapshot{};
  for(unsigned i=0;i<snapshot.size();++i) snapshot[i]=m.read(5+i);
  m.idle(100);
  for(unsigned i=0;i<snapshot.size();++i) native_require(m.read(5+i)==snapshot[i],"held completion changed or tore");
  m.check_memory();
}
static void ack(NativeGraphicsMachine &m) {
  m.write(3,2);native_require((m.read(2)&7)==1,"MMIO completion ACK failed");
}
static void run_draw(NativeGraphicsMachine &m,BlitCommand c) {
  c.tag=uint16_t(commands+1);const auto d=native_descriptor(c);const auto expected=blit_reference(m.golden,c);
  m.stage(d);m.write(3,1);check_result(m,d,expected.error,expected.samples,expected.pixels);ack(m);++draws;
}
static void run_byte(NativeGraphicsMachine &m,bool write,uint32_t address,uint8_t value) {
  const auto d=native_byte(write,address,value,uint16_t(commands+1));
  if(write) blit_byte(m.golden,address,value);
  const auto expected=write?0:blit_byte(m.golden,address);
  m.stage(d);m.write(3,1);check_result(m,d,0);
  native_require(m.read32(8)==unsigned(expected),"byte-lane MMIO readback mismatch");
  native_require(m.read32(0x18)==unsigned(!write) && m.read32(0x1c)==unsigned(write),"byte operation transaction counts wrong");
  ack(m);++byte_ops;
}
int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);
    for(const auto [period,phase]:{std::pair{4u,0u},{5u,3u},{7u,9u}}) {
      NativeGraphicsMachine m(period,phase);
      native_require(m.read(0)==0xcb && m.read(1)==1 && (m.read(2)&7)==1,"MMIO reset/identity wrong");
      for(unsigned n=0;n<36;++n) native_require(m.read(0x40+n)==0,"shadow descriptor not reset");
      native_require(!m.dut.initialized,"test missed early initialization submission");
      run_byte(m,false,0x7fffff,0);
      // A descriptor remains isolated from subsequent shadow writes and busy
      // submissions, including clear-reject+GO and ACK+GO on held completion.
      BlitCommand c;c.fill=true;c.fill_covered=false;c.width=320;c.height=204;c.tag=0xabcd;
      const auto d=native_descriptor(c);const auto expected=blit_reference(m.golden,c);
      m.stage(d);m.write(4,1);m.write(3,1);
      NativeDescriptor poison;poison.fill(255);m.stage(poison);m.write(3,5);
      native_require((m.read(2)&0x12)==0x12 && m.dut.irq,"busy resubmission not rejected/interrupting");
      m.write(3,4);native_require(!(m.read(2)&16),"sticky rejection could not clear");
      check_result(m,d,expected.error,expected.samples,expected.pixels);
      native_require(m.dut.irq,"completion interrupt missing");
      m.write(3,3);native_require((m.read(2)&0x17)==0x11,"ACK+GO incorrectly reused held result");
      m.write(3,4);native_require(!m.dut.irq,"IRQ did not clear after ACK/rejection clear");
      ++draws;
      for(uint32_t base:{0u,0x1ffffcu,0x200000u,0x3ffffcu,0x400000u,0x5ffffcu,0x600000u,0x7ffffcu})
        for(unsigned lane=0;lane<4;++lane) {
          run_byte(m,true,base+lane,uint8_t(0x31+lane*43));run_byte(m,false,base+lane,0);
        }
      m.peer_load=false;m.idle(100);
      for(unsigned n:{0u,7u,10u,12u,14u,20u,22u,24u,26u,28u,30u,32u,34u}) {
        auto bad=native_descriptor(BlitCommand{});bad[n]|=128;bad[3]=uint8_t(commands+1);bad[4]=0xf0;
        const auto reads=m.memory.read_count,writes=m.memory.write_count;
        m.stage(bad);m.write(3,1);check_result(m,bad,5);
        native_require(m.memory.write_count==writes && m.memory.read_count==reads,"malformed descriptor accessed physical memory");
        ack(m);++format_errors;
      }
      m.peer_load=true;
      std::mt19937 random{0x1644204};
      for(unsigned n=0;n<48;++n) {
        c=BlitCommand{};c.fill=n%8==0;c.fill_covered=n%3;c.bpp4=n%2;
        c.source=0x4001;c.source_width=1+random()%32;c.source_height=1+random()%32;
        c.source_stride=40;c.width=1+random()%100;c.height=1+random()%70;c.x=int(random()%350)-25;c.y=int(random()%230)-20;
        c.flip_x=n%3==0;c.flip_y=n%5==0;c.palette=uint8_t(n%16);c.band=uint8_t(n%16);
        c.fill_index=uint8_t(n*17);c.destination+=2*(n%2);c.destination_stride=640+2*(n%3);
        run_draw(m,c);
      }
      for(unsigned error=1;error<=4;++error) {
        c=BlitCommand{};
        if(error==1) c.width=0;
        if(error==2) c.destination_stride=641;
        if(error==3) c.destination=0x7ffffe;
        if(error==4) c.source=c.destination;
        run_draw(m,c);
      }
      // An accepted command held behind controller backpressure is canceled
      // jointly. New work cannot consume an old toggle/result after restart.
      c=BlitCommand{};c.fill=true;c.width=320;c.height=204;m.stage(native_descriptor(c));
      m.dut.memory_stall=1;m.write(3,1);m.idle(900);
      native_require((m.read(2)&3)==2,"stalled draw did not remain busy");
      m.reset();m.idle(15000);native_require((m.read(2)&7)==1 && !m.dut.irq,"reset leaked command/result/IRQ");
      run_byte(m,true,0x10003,0xe1);run_byte(m,false,0x10003,0);
      m.write(4,1);m.allow_fault=true;m.dut.test_fault=1;m.idle(40);
      native_require((m.read(2)&32) && m.dut.irq,"synchronized hardware fault/IRQ missing");
      m.reset();m.allow_fault=false;m.idle(15000);
      native_require(!(m.read(2)&0xb4) && !m.dut.irq,"joint reset did not clear fault/rejection/result/IRQ");
      m.write(0xff,0xff);native_require(m.read(0xff)==0 && m.read(0)==0xcb,"reserved MMIO location changed identity/state");
    }
    if(argc>1) {
      std::ofstream out(argv[1]);
      out<<"{\n  \"scope\": \"dual-clock MMIO, real blitter/elastic arbiter/SDRAM against independent pin/pixel models; direct register driver, no CPU firmware or scanout\",\n"
         <<"  \"completed_commands\": "<<commands<<",\n  \"draw_fill_commands\": "<<draws<<",\n  \"byte_commands\": "<<byte_ops
         <<",\n  \"format_errors\": "<<format_errors<<",\n  \"clock_phase_configurations\": 3,\n  \"physical_testing\": false,\n  \"passed\": true\n}\n";
      native_require(bool(out),"could not write MMIO evidence");
    }
    std::cout<<"PASS: "<<commands<<" held MMIO results; command isolation, byte lanes, exact draw pixels, errors, IRQ, clock phases and reset\n";
    return 0;
  } catch(const std::exception &e) {std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
