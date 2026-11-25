#include "Vcb_board_control.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <fstream>
#include <iostream>
#include <stdexcept>

static void require(bool ok,const char *why) { if(!ok) throw std::runtime_error(why); }
class Control {
  std::array<unsigned,3> edges{};
  unsigned audio_count=0;
  uint64_t now=0,next_sys=504,next_pixel=292,next_audio=137;
  bool previous_async=true;
public:
  Vcb_board_control dut;
  bool audio_stopped=false,sys_stopped=false,strobe_enabled=true;
  unsigned reset_events=0;
  Control() {
    dut.sys_clk=0;dut.pixel_clk=0;dut.audio_clk=0;
    dut.reset_button=0;dut.sys_locked=0;dut.video_locked=0;
    dut.running=0;dut.audio_ready=0;dut.audio_underrun=0;dut.audio_frame_strobe=0;
    dut.eval(); inspect(false,false,false);
  }
  void inspect(bool sys,bool pixel,bool audio) {
    const bool async=dut.reset_button || !dut.sys_locked || !dut.video_locked;
    require(bool(dut.async_reset)==async,"joint asynchronous reset equation wrong");
    if(async) { if(!previous_async) ++reset_events; edges={}; }
    else {
      if(sys && edges[0]<3) ++edges[0];
      if(pixel && edges[1]<3) ++edges[1];
      if(audio && edges[2]<3) ++edges[2];
    }
    previous_async=async;
    require(bool(dut.sys_reset)==(edges[0]<3) && bool(dut.pixel_reset)==(edges[1]<3) && bool(dut.audio_reset)==(edges[2]<3),"reset did not assert without clocks or release after exactly three local edges");
    if(dut.sys_reset || !dut.running || !dut.audio_ready || dut.audio_underrun || !dut.audio_alive)
      require(!dut.amplifier_enable,"amplifier enabled without every required condition");
  }
  void changed() { dut.eval();inspect(false,false,false); }
  void tick() {
    now=std::min(next_sys,std::min(next_pixel,next_audio));
    bool sys=false,pixel=false,audio=false;
    if(next_sys==now) { next_sys+=504;if(!sys_stopped) {dut.sys_clk=!dut.sys_clk;sys=dut.sys_clk;} }
    if(next_pixel==now) { next_pixel+=1280;dut.pixel_clk=!dut.pixel_clk;pixel=dut.pixel_clk; }
    if(next_audio==now) {
      next_audio+=2625;
      if(!audio_stopped) {
        dut.audio_clk=!dut.audio_clk;audio=dut.audio_clk;
        if(!dut.audio_clk) { dut.audio_frame_strobe=strobe_enabled && (++audio_count%256==0); }
      }
    }
    dut.eval();inspect(sys,pixel,audio);
  }
  void idle(unsigned events) { while(events--) tick(); }
};
int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);
    Control c;c.idle(100);c.dut.sys_locked=1;c.changed();c.idle(100);
    require(c.dut.sys_reset && c.dut.pixel_reset && c.dut.audio_reset,"one PLL unlocked did not hold every domain");
    c.dut.video_locked=1;c.changed();c.idle(10000);
    require(!c.dut.sys_reset && !c.dut.pixel_reset && !c.dut.audio_reset && c.dut.audio_alive,"clock/reset startup did not complete");
    c.dut.running=1;c.dut.audio_ready=1;c.changed();require(c.dut.amplifier_enable,"healthy stream did not enable amplifier");
    c.audio_stopped=true;c.idle(30000);require(!c.dut.audio_alive && !c.dut.amplifier_enable,"stopped audio clock did not mute amplifier");
    c.audio_stopped=false;c.idle(10000);require(c.dut.amplifier_enable,"audio activity did not recover after restart");
    c.strobe_enabled=false;c.idle(30000);require(!c.dut.amplifier_enable,"running clock with stopped formatter was not muted");
    c.strobe_enabled=true;c.idle(10000);require(c.dut.amplifier_enable,"formatter activity did not recover");
    c.dut.audio_underrun=1;c.changed();require(!c.dut.amplifier_enable,"underrun did not mute amplifier");
    c.dut.audio_underrun=0;c.dut.running=0;c.changed();require(!c.dut.amplifier_enable,"game stop did not mute amplifier");
    c.sys_stopped=true;c.audio_stopped=true;c.dut.sys_locked=0;c.changed();
    require(c.dut.sys_reset && c.dut.pixel_reset && c.dut.audio_reset,"PLL loss failed asynchronous assertion with stopped clocks");
    c.dut.sys_locked=1;c.changed();c.idle(200);
    require(c.dut.sys_reset && c.dut.audio_reset && !c.dut.pixel_reset,"stopped domains released reset without local edges");
    c.sys_stopped=false;c.audio_stopped=false;c.idle(1000);
    c.dut.reset_button=1;c.changed();c.idle(73);c.dut.reset_button=0;c.changed();c.idle(1000);
    require(c.reset_events>=2,"missing reset/lock-loss cases");
    if(argc>1) {
      std::ofstream evidence(argv[1]);
      evidence<<"{\n  \"scope\": \"board reset and audio activity control RTL; ideal clocks and lock inputs, no PLL or physical timing\",\n"
              <<"  \"reset_events\": "<<c.reset_events<<",\n  \"local_release_edges\": 3,\n"
              <<"  \"physical_testing\": false,\n  \"passed\": true\n}\n";
      require(bool(evidence),"could not write evidence");
    }
    std::cout<<"PASS: joint asynchronous assertion, three-edge local release, delayed PLL lock, stopped clocks, audio watchdog, amplifier gating and restart\n";
    return 0;
  } catch(const std::exception &error) {std::cerr<<"FAIL: "<<error.what()<<"\n";return 1;}
}
