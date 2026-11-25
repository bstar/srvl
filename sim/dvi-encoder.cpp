#include "Vdvi_encoder_top.h"
#include "verilated.h"
#include "tmds-model.hpp"
#include <array>
#include <fstream>
#include <iostream>
#include <map>
#include <random>
#include <set>
#include <vector>

static void require(bool ok,const char *why) { if(!ok) throw std::runtime_error(why); }
class Encoder {
  TmdsModel single;
  std::array<TmdsModel,3> rgb_models;
public:
  Vdvi_encoder_top dut;
  uint64_t cycles=0,active_symbols=0,rgb_pixels=0;
  std::set<unsigned> codebook;
  Encoder() { dut.clk=0; dut.reset=1; dut.de=0; dut.c0=0; dut.c1=0; dut.data=0; dut.rgb_de=0; dut.hsync=0; dut.vsync=0; dut.rgb=0; }
  void tick() {
    const auto expected=single.encode(dut.data,dut.de && !dut.reset,(dut.c1<<1)|dut.c0);
    std::array<uint16_t,3> expected_rgb{};
    for(unsigned lane=0;lane<3;++lane) {
      const auto nibble=uint8_t((dut.rgb>>(lane*4))&15);
      expected_rgb[lane]=rgb_models[lane].encode(uint8_t(nibble*17),dut.rgb_de && !dut.reset,lane?0:((dut.vsync<<1)|dut.hsync));
    }
    dut.clk=0; dut.eval(); dut.clk=1; dut.eval(); ++cycles;
    if(dut.reset) {
      require(dut.symbol==TmdsModel::control(0),"TMDS reset control symbol wrong");
      single.disparity=0; for(auto &model:rgb_models) model.disparity=0;
      return;
    }
    require(dut.symbol==expected,"TMDS word/disparity decision differs from independent model");
    if(dut.de) {
      require(TmdsModel::decode(dut.symbol)==dut.data,"TMDS decode did not recover the original byte");
      codebook.insert(dut.symbol); ++active_symbols;
    }
    require((dut.symbols>>30)==0x01f,"forwarded clock word has wrong polarity/order");
    for(unsigned lane=0;lane<3;++lane) {
      const unsigned word=(dut.symbols>>(lane*10))&1023;
      require(word==expected_rgb[lane],"RGB lanes, control placement or disparity are misaligned");
      if(dut.rgb_de) require(TmdsModel::decode(word)==(((dut.rgb>>(lane*4))&15)*17),"RGB444 expansion changed a channel");
    }
    if(dut.rgb_de) ++rgb_pixels;
  }
  void reset() { dut.reset=1; tick(); dut.reset=0; }
  void byte(unsigned value) { dut.de=1; dut.data=value; tick(); }
};
int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);
    // Discover reachable disparity states and ordinary input-byte prefixes.
    // No production register is forced to reach a test state.
    std::map<int,std::vector<uint8_t>> prefixes{{0,{}}};
    for(bool changed=true;changed;) {
      changed=false; const auto old=prefixes;
      for(const auto &[state,path]:old) for(unsigned byte=0;byte<256;++byte) {
        TmdsModel reference; reference.disparity=state; reference.encode(uint8_t(byte),true);
        if(!prefixes.count(reference.disparity)) {
          auto next=path; next.push_back(uint8_t(byte)); prefixes[reference.disparity]=next; changed=true;
        }
      }
    }
    require(prefixes.size()==9,"unexpected reachable TMDS disparity state space");
    Encoder e;
    for(const auto &[state,path]:prefixes) for(unsigned byte=0;byte<256;++byte) {
      e.reset(); for(auto prefix:path) e.byte(prefix); e.byte(byte);
    }
    require(e.codebook.size()==460,"active TMDS codebook is not the DVI-defined 460 words");
    for(unsigned bits=0;bits<4;++bits) {
      e.byte(0); e.byte(255); e.dut.de=0; e.dut.c0=bits&1; e.dut.c1=bits>>1; e.tick();
    }
    std::mt19937 random(0xd7100252);
    for(unsigned n=0;n<200000;++n) {
      e.dut.data=random()&255; e.dut.de=(random()%32)!=0; e.dut.c0=random()&1; e.dut.c1=random()&1;
      e.dut.rgb=random()&4095; e.dut.rgb_de=(random()%32)!=0; e.dut.hsync=random()&1; e.dut.vsync=random()&1;
      if(n%1237==0) e.reset();
      e.tick();
    }
    for(unsigned color=0;color<4096;++color) { e.dut.rgb=color; e.dut.rgb_de=1; e.tick(); }
    // A full transport raster verifies control/video transitions at real edges.
    for(unsigned y=0;y<525;++y) for(unsigned x=0;x<800;++x) {
      e.dut.hsync=!(x>=656 && x<752); e.dut.vsync=!(y>=490 && y<492);
      e.dut.rgb_de=x<640 && y<480; e.dut.rgb=(x*17+y*97)&4095; e.tick();
    }
    if(argc==2) {
      std::ofstream out(argv[1]);
      out<<"{\n  \"scope\": \"registered DVI TMDS encoding and RGB/control lane mapping; no physical serializer/board timing\",\n"
         <<"  \"cycles\": "<<e.cycles<<",\n  \"reachable_disparity_states\": "<<prefixes.size()<<",\n"
         <<"  \"exhaustive_state_byte_cases\": "<<prefixes.size()*256<<",\n  \"active_codewords\": "<<e.codebook.size()<<",\n"
         <<"  \"checked_active_symbols\": "<<e.active_symbols<<",\n  \"checked_rgb_pixels\": "<<e.rgb_pixels<<",\n"
         <<"  \"physical_testing\": false,\n  \"passed\": true\n}\n";
    }
    std::cout<<"PASS: all 9 reachable disparity states x 256 bytes, 460 active codewords, control/reset/random sequences, all 4096 RGB444 colors and complete 800x525 raster\n";
    return 0;
  } catch(const std::exception &error) { std::cerr<<"FAIL: "<<error.what()<<"\n"; return 1; }
}
