#include "native-graphics-model.hpp"
#include <fstream>
#include <iostream>
#include <set>

static BlitCommand expected_draw(uint16_t tag) {
  BlitCommand c;c.tag=tag;c.source=0x4003;c.source_width=8;c.source_height=8;c.source_stride=11;c.fill_covered=false;
  if(tag==0x2001) { c.fill=true;c.transparent=false;c.width=320;c.height=204; }
  else if(tag==0x2002) { c.flip_x=c.flip_y=true;c.band=3;c.x=-3;c.y=-2;c.width=37;c.height=23; }
  else if(tag==0x2003) { c.bpp4=true;c.flip_y=true;c.palette=11;c.band=7;c.source_width=5;c.source_height=7;c.source_stride=5;c.x=298;c.y=191;c.width=19;c.height=11; }
  else if(tag==0x2004) { c.transparent=false;c.source_width=c.source_height=c.source_stride=1;c.band=4;c.x=48;c.y=17;c.width=7;c.height=5; }
  else if(tag==0x2005) { c.fill=true;c.fill_covered=true;c.transparent=false;c.fill_index=0;c.band=6;c.x=319;c.y=203;c.width=c.height=3; }
  else if(tag==0x2006) c.width=0;
  else if(tag==0x2007) c.destination_stride=641;
  else if(tag==0x2008) c.source=c.destination;
  else if(tag==0x2009) { c.transparent=false; /* malformed format is checked separately */ }
  else if(tag==0x2ff0) { c.fill=true;c.fill_covered=true;c.transparent=false;c.fill_index=0x27;c.band=8;c.x=120;c.y=80;c.width=c.height=16; }
  else throw std::runtime_error("ROM submitted an unexpected draw tag");
  return c;
}
int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);
    uint64_t total_commands=0,total_irq_fetches=0,total_cpu_writes=0,total_fetches=0,total_cycles=0;
    unsigned configuration=0;
    for(const auto [period,phase]:{std::pair{4u,0u},{5u,3u},{7u,9u}}) {
      NativeGraphicsMachine m(period,phase);
      for(unsigned epoch=0;epoch<2;++epoch) {
      if(epoch) { m.before_cpu_edge={};m.reset(); }
      const auto boot_start=m.cycles;
      NativeDescriptor shadow{};
      bool outstanding=false;unsigned accepted=0,rejected=0,irq_entries=0,uploads=0,reads=0,draws=0;
      std::set<uint16_t> seen;
      m.before_cpu_edge=[&]() {
        if(m.dut.trace_sync) { ++total_fetches; }
        if(!m.dut.trace_write) return;
        ++total_cpu_writes;
        const unsigned address=m.dut.trace_address;const uint8_t data=m.dut.trace_data;
        if(address>=0x4440 && address<0x4464) shadow.at(address-0x4440)=data;
        if(address!=0x4403) return;
        if(data&1) {
          if(outstanding) { ++rejected; }
          else {
            outstanding=true;++accepted;
            const uint16_t tag=unsigned(shadow[3])|(unsigned(shadow[4])<<8);
            const unsigned op=shadow[0]&3;
            const uint32_t destination=unsigned(shadow[8])|(unsigned(shadow[9])<<8)|(unsigned(shadow[10])<<16);
            if(op==2) {
              native_require(uploads<96 && tag==0x1000+uploads && destination==0x4003+uploads && shadow[35]==uint8_t(uploads*17),"ROM asset upload/order/data mismatch");
              blit_byte(m.golden,destination,shadow[35]);++uploads;
            } else if(op==3) {
              const std::array<uint32_t,3> probes{0x4003,0x4004,0x4062};
              native_require(reads<3 && destination==probes[reads] && tag==0x1000+reads,"ROM byte probe/order mismatch");++reads;
            } else {
              native_require(seen.insert(tag).second,"ROM duplicated an accepted draw");
              const auto c=expected_draw(tag);auto descriptor=native_descriptor(c);
              if(tag==0x2009) descriptor[0]=0x80;
              native_require(descriptor==shadow,"ROM draw descriptor differs from independent command specification");
              if(tag!=0x2009) blit_reference(m.golden,c);
              ++draws;
            }
          }
        }
        if(data&2) {
          native_require(outstanding,"ROM acknowledged a nonexistent result");outstanding=false;
          if(m.dut.irq) ++irq_entries;
        }
      };
      const auto deadline=m.cycles+4000000;
      while(m.dut.diagnostic!=0xa5 && m.dut.diagnostic!=0xe0 && m.cycles<deadline) m.tick();
      native_require(m.dut.diagnostic==0xa5,"CPU diagnostic failed/timed out, phase "+std::to_string(phase)+", PC="+std::to_string(m.dut.trace_address));
      m.idle(1000);m.check_memory();
      native_require(accepted==109 && uploads==96 && reads==3 && draws==10 && seen.size()==10 && !outstanding && rejected==1 && irq_entries==1,
                     "CPU did not exercise the complete diagnostic/IRQ protocol exactly once");
      native_require(!m.dut.irq,"CPU handler did not acknowledge completion IRQ");
      total_commands+=accepted;total_irq_fetches+=irq_entries;total_cycles+=m.cycles-boot_start;
      }
      m.preview("native-scene-"+std::to_string(configuration++)+".ppm");
    }
    if(argc>1) {
      std::ofstream out(argv[1]);
      out<<"{\n  \"scope\": \"actual pinned R65C02 executes original diagnostic ROM through dual-clock MMIO, real blitter/arbiter/SDRAM and unchanged pin/pixel models; no native scanout, frame ownership or complete board timing\",\n"
         <<"  \"completed_cpu_submissions\": "<<total_commands<<",\n  \"cpu_instruction_fetches\": "<<total_fetches
         <<",\n  \"cpu_write_cycles\": "<<total_cpu_writes<<",\n  \"acknowledged_cpu_irq_completions\": "<<total_irq_fetches
         <<",\n  \"graphics_cycles\": "<<total_cycles<<",\n  \"clock_phase_configurations\": 3,\n  \"cold_and_warm_boots\": 6,\n  \"host_asset_uploads\": 0,\n  \"physical_testing\": false,\n  \"passed\": true\n}\n";
      native_require(bool(out),"could not record native CPU graphics evidence");
    }
    std::cout<<"PASS: actual CPU diagnostic ROM, "<<total_commands<<" submissions, CPU-uploaded assets, scaled pixels, errors, isolated commands and IRQ across three clock phases\n";
    return 0;
  } catch(const std::exception &e) {std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
