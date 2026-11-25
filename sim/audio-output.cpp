#include "Vlynx_audio_output.h"
#include "verilated.h"
#include "audio-model.hpp"
#include "i2s-decoder.hpp"
#include <cmath>
#include <deque>
#include <fstream>
#include <iostream>
#include <random>
#include <vector>

static void require(bool ok,const char *why) { if(!ok) throw std::runtime_error(why); }
class Audio {
  uint64_t now=0,next_audio=137;
  unsigned audio_half;
  AudioModel reference;
  I2sDecoder decoder;
  std::deque<AudioModel::Pair> snapshots,frames;
public:
  Vlynx_audio_output dut;
  uint64_t cycles=0,serial_frames=0,source_snapshots=0,cancelled_snapshots=0,silent_frames=0;
  bool pause_sys=false,expect_underrun=false;
  AudioModel::Pair last_pair{};
  explicit Audio(unsigned half=2625):audio_half(half) {
    dut.clk=0; dut.reset=1; dut.audio_clk=0; dut.audio_reset=1; dut.enable=0;
    dut.input_left=0; dut.input_right=0; dut.eval(); dut.clk=1; dut.eval();
  }
  void audio_edge() {
    if(dut.audio_reset) { decoder.reset(); return; }
    if(dut.frame_strobe) {
      if(dut.frame_valid) {
        require(!snapshots.empty(),"I2S frame consumed an unowned stereo pair");
        frames.push_back(snapshots.front()); snapshots.pop_front();
      } else { frames.emplace_back(0,0); ++silent_frames; }
    }
    if(const auto decoded=decoder.observe(dut.bclk,dut.ws,dut.sd)) {
      require(!frames.empty(),"I2S decoder completed an unexpected frame");
      require(*decoded==frames.front(),"I2S channels/data differ from one coherent source snapshot");
      last_pair=*decoded; frames.pop_front(); ++serial_frames;
    }
    if(!expect_underrun) require(!dut.underrun,"unexpected I2S underrun");
  }
  void advance(uint64_t target) {
    while(next_audio<target) {
      dut.audio_clk=!dut.audio_clk; dut.eval();
      if(dut.audio_clk) audio_edge();
      next_audio+=audio_half;
    }
    now=target;
  }
  void tick() {
    advance(now+504);
    if(!pause_sys) { dut.clk=0; dut.eval(); }
    advance(now+504);
    if(!pause_sys) {
      const auto expected=reference.output(dut.enable);
      reference.step(int16_t(dut.input_left),int16_t(dut.input_right),dut.enable,dut.reset);
      dut.clk=1; dut.eval();
      if(!dut.reset) {
        require(AudioModel::Pair{int16_t(dut.filtered_left),int16_t(dut.filtered_right)}==reference.output(dut.enable),"fixed-point filter differs from independent wide-arithmetic model");
        if(dut.snapshot_valid) {
          require(AudioModel::Pair{int16_t(dut.snapshot_left),int16_t(dut.snapshot_right)}==expected,"mailbox captured a torn or incorrectly filtered stereo pair");
          snapshots.push_back(expected); ++source_snapshots;
        }
      }
    }
    ++cycles;
  }
  void idle(unsigned count) { while(count--) tick(); }
  void reset() {
    dut.reset=1; dut.audio_reset=1; pause_sys=false;
    cancelled_snapshots+=snapshots.size()+frames.size(); snapshots.clear(); frames.clear(); decoder.reset();
    idle(32); dut.reset=0; dut.audio_reset=0; idle(32);
  }
  void signal(int16_t left,int16_t right) { dut.input_left=uint16_t(left); dut.input_right=uint16_t(right); }
  void settled(int16_t left,int16_t right) {
    signal(left,right); idle(100000);
    require(last_pair==AudioModel::Pair{left,right},"signed DC/full-scale did not settle exactly");
  }
  double frequency(unsigned hz) {
    const auto base=cycles;
    double input_power=0,output_power=0;
    for(unsigned n=0;n<768000;++n) {
      const auto v=int16_t(std::lround(12000*std::sin(2*std::acos(-1.0)*hz*(cycles-base)/64000000.0)));
      signal(v,int16_t(-v)); tick();
      if(n>=128000) {
        input_power+=double(v)*v;
        output_power+=double(int16_t(dut.filtered_left))*int16_t(dut.filtered_left);
      }
    }
    const double measured=std::sqrt(output_power/input_power),a=1.0/1024;
    const double w=2*std::acos(-1.0)*hz/64000000;
    const double expected=std::pow(a/std::sqrt(1+(1-a)*(1-a)-2*(1-a)*std::cos(w)),4);
    require(std::abs(measured-expected)<expected*0.02+1.0/12000,"measured filter response differs from independent transfer function");
    std::cout<<"PASS: "<<hz<<" Hz filter gain "<<20*std::log10(measured)<<" dB\n";
    return 20*std::log10(measured);
  }
};
int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);
    Audio a; a.reset(); a.dut.enable=1;
    a.settled(32767,-32768); a.settled(-32768,32767); a.settled(12345,-23456);
    std::mt19937 random(0xa048000);
    for(unsigned n=0;n<200000;++n) { a.signal(int16_t(random()),int16_t(random())); a.tick(); }
    a.dut.enable=0; a.idle(10000); require(a.last_pair==AudioModel::Pair{0,0},"mute did not produce a whole silent stereo frame");
    a.dut.enable=1; a.settled(8000,-4000);
    const auto gain_1k=a.frequency(1000),gain_24k=a.frequency(24000),gain_32k=a.frequency(32000);
    // Let the system clock stop while the independent I2S clock continues.
    // One already-prefetched frame may play, then whole frames must be silent.
    a.expect_underrun=true; a.pause_sys=true; a.idle(20000);
    require(a.dut.underrun && a.dut.underrun_count>0 && a.last_pair==AudioModel::Pair{0,0},"source-clock stop failed to produce reported whole-frame silence");
    a.pause_sys=false; a.settled(4000,-2000);
    a.reset(); a.expect_underrun=false; a.settled(-1000,2000);
    require(!a.dut.underrun_count,"joint reset retained an old underrun");
    Audio b(2623); b.reset(); b.dut.enable=1; b.settled(-32768,32767); b.settled(3000,-7000);
    require(a.serial_frames>1000 && b.serial_frames>100,"insufficient decoded audio frames");
    if(argc==2) {
      std::ofstream out(argv[1]);
      out<<"{\n  \"scope\": \"fixed-point filter, coherent stereo mailbox and pin-decoded I2S; no analog/board timing acceptance\",\n"
         <<"  \"sys_cycles\": "<<a.cycles+b.cycles<<",\n  \"decoded_frames\": "<<a.serial_frames+b.serial_frames
         <<",\n  \"source_snapshots\": "<<a.source_snapshots+b.source_snapshots<<",\n  \"reset_cancelled_buffers\": "<<a.cancelled_snapshots
         <<",\n  \"gain_db\": {\"1000\": "<<gain_1k<<", \"24000\": "<<gain_24k<<", \"32000\": "<<gain_32k<<"},\n"
         <<"  \"independent_audio_half_periods\": [2625,2623],\n  \"sys_half_period\": 504,\n"
         <<"  \"source_clock_stop_and_recovery\": true,\n  \"physical_testing\": false,\n  \"passed\": true\n}\n";
    }
    std::cout<<"PASS: signed full-scale, randomized stereo, mute, pin-decoded I2S, independent clocks, source-stop silence and joint-reset recovery; "<<a.serial_frames+b.serial_frames<<" frames\n";
    return 0;
  } catch(const std::exception &error) { std::cerr<<"FAIL: "<<error.what()<<"\n"; return 1; }
}
