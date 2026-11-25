// Test infrastructure only. The enhanced system runs its own demo ROM; this
// harness supplies clocks and the independent SDRAM pin model, captures the
// transport frames and compares them with an independent statement of what the
// demo draws. It renders nothing for the system under test.
#include "Venhanced_system.h"
#include "verilated.h"
#include "scaled-blitter-model.hpp"
#include "sdram-model.hpp"
#include <array>
#include <fstream>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>

static void require(bool ok,const std::string &why) { if(!ok) throw std::runtime_error(why); }
using Image=std::vector<uint16_t>;                 // 320x204 RGB444
// Independent literals: these deliberately do not include the generated ABI.
static const std::array<uint16_t,16> palette{0x000,0x113,0xf00,0x0f0,0x00f,0xff0,0xf0f,0x0ff,
                                              0xfff,0xf80,0x8f0,0x08f,0xf08,0x80f,0x888,0x444};
static const std::array<uint8_t,64> sprite{0,0,2,2,2,2,0,0, 0,2,3,3,3,3,2,0, 2,3,4,5,5,4,3,2, 2,3,5,8,9,5,3,2,
                                           2,3,5,10,11,5,3,2, 2,3,4,5,5,4,3,2, 0,2,6,7,12,13,2,0, 0,0,14,15,15,14,0,0};
static const uint32_t surface_address[2]={0x100000,0x140000};
// Frame n is drawn into the surface that is not displayed: the first into 1.
static Image expected_frame(std::vector<uint32_t> &scratch,unsigned n) {
  const uint32_t destination=surface_address[(n+1)%2];
  BlitCommand clear;clear.fill=true;clear.fill_covered=true;clear.transparent=false;clear.fill_index=1;
  clear.destination=destination;clear.width=320;clear.height=204;
  require(blit_reference(scratch,clear).error==0,"reference clear rejected");
  for(unsigned i=0;i<4;++i) {
    BlitCommand c;c.source=0x4000;c.source_width=c.source_height=8;c.source_stride=8;c.destination=destination;
    c.band=uint8_t(i);c.x=uint8_t(3*n+61*i);c.y=int(8+46*i);c.width=c.height=16+2*((n+4*i)&15);
    require(blit_reference(scratch,c).error==0,"reference sprite rejected");
  }
  Image image(320*204);
  for(unsigned y=0;y<204;++y) for(unsigned x=0;x<320;++x) {
    const uint32_t address=destination+y*640+x*2;
    const unsigned word=blit_byte(scratch,address)|(unsigned(blit_byte(scratch,address+1))<<8);
    image[y*320+x]=(word&0x1000) ? palette.at(word&255):0;
  }
  return image;
}

struct Machine {
  Venhanced_system dut;
  SdramModel memory;
  // Time unit: half a picosecond. 64 MHz and 25.2 MHz with unrelated phase.
  uint64_t now=0,next_system=0,next_video,system_cycles=0,video_cycles=0;
  const uint64_t system_half=15625,video_half;
  const unsigned cpu_divide,cpu_phase;
  std::vector<uint16_t> capture=std::vector<uint16_t>(640*480);
  uint64_t captured=0,frames=0,last_vsync=0,vsync_periods=0;
  bool previous_vsync=true,frame_ready=false,allow_ownership_fault=false;
  Machine(uint64_t video_half_period,uint64_t video_offset,unsigned divide,unsigned phase)
    :next_video(video_offset),video_half(video_half_period),cpu_divide(divide),cpu_phase(phase) {
    dut.clk=0;dut.memory_clk=0;dut.video_clk=0;dut.reset=1;dut.video_reset=1;dut.dq_in=0;dut.eval();
    memory.expect_initialization();
    while(system_cycles<64) step();
    dut.reset=0;dut.video_reset=0;
  }
  void system_edge() {
    if(dut.clk) {
      dut.clk=0;dut.dq_in=memory.dq();dut.eval();
      memory.edge({bool(dut.sdram_cke),bool(dut.sdram_cs_n),bool(dut.sdram_ras_n),bool(dut.sdram_cas_n),bool(dut.sdram_we_n),bool(dut.dq_oe),
                   uint16_t(dut.sdram_a),uint8_t(dut.sdram_ba),uint8_t(dut.sdram_dqm),uint32_t(dut.dq_out)});
      dut.dq_in=memory.dq();dut.eval();
      return;
    }
    // The CPU/memory clock is an integer division of the system clock.
    dut.memory_clk=((system_cycles+cpu_phase)%cpu_divide)<cpu_divide/2;
    dut.clk=1;dut.eval();++system_cycles;
    require(!dut.protocol_fault,"memory/engine/scanout protocol fault");
    require(allow_ownership_fault || !dut.ownership_fault,"graphics write into a surface owned by scanout");
    require(!dut.underrun,"native scanout line underrun");
  }
  void video_edge() {
    dut.video_clk=!dut.video_clk;dut.eval();
    if(!dut.video_clk) return;
    ++video_cycles;
    if(dut.video_de) {
      require(dut.video_x<640 && dut.video_y<480,"active pixel outside the transport raster");
      capture[dut.video_y*640u+dut.video_x]=dut.video_rgb;++captured;
      if(dut.video_x==639 && dut.video_y==479) {
        require(captured==640u*480u,"transport frame did not carry 640x480 active pixels");
        captured=0;frame_ready=true;++frames;
      }
    } else require(dut.video_rgb==0,"color outside active video");
    if(previous_vsync && !dut.video_vsync) {
      if(last_vsync) { require(video_cycles-last_vsync==800u*525u,"vertical period is not 800x525 pixel clocks");++vsync_periods; }
      last_vsync=video_cycles;
    }
    previous_vsync=dut.video_vsync;
  }
  void step() {
    if(next_system<=next_video) { now=next_system;next_system+=system_half;system_edge(); }
    else { now=next_video;next_video+=video_half;video_edge(); }
  }
  // Returns the 320x204 image if the frame is an exact 2x canvas with black
  // bars; an entirely black transport frame returns an empty image.
  Image next_frame() {
    frame_ready=false;
    const uint64_t deadline=system_cycles+3000000;
    while(!frame_ready && system_cycles<deadline) step();
    require(frame_ready,"no transport frame");
    bool any=false;
    for(const auto pixel:capture) any=any || pixel;
    if(!any) return {};
    Image image(320*204);
    for(unsigned y=0;y<480;++y) for(unsigned x=0;x<640;++x) {
      const uint16_t pixel=capture[y*640+x];
      if(y<36 || y>=444) require(pixel==0,"bar rows are not black");
      else if((x%2)==0 && ((y-36)%2)==0) image[((y-36)/2)*320+x/2]=pixel;
      else require(pixel==image[((y-36)/2)*320+x/2],"canvas is not an exact 2x replication");
    }
    return image;
  }
};

struct Result { unsigned shown=0,distinct=0,repeated=0,blank=0; uint64_t cycles=0; };
static Result run_demo(uint64_t video_half,uint64_t video_offset,unsigned divide,unsigned phase,unsigned wanted,const char *preview) {
  Machine m(video_half,video_offset,divide,phase);
  std::vector<uint32_t> scratch=m.memory.memory;
  for(unsigned i=0;i<sprite.size();++i) blit_byte(scratch,0x4000+i,sprite[i]);
  std::map<unsigned,Image> reference;
  auto expected=[&](unsigned n) -> const Image & {
    // Earlier frames are rendered in order because each surface keeps history.
    for(unsigned k=unsigned(reference.size());k<=n;++k) reference[k]=expected_frame(scratch,k);
    return reference.at(n);
  };
  Result r;int last=-1;
  while(r.distinct<wanted) {
    const Image image=m.next_frame();
    require(m.dut.diagnostic!=0xe0,"demo ROM reported failure");
    if(image.empty()) { require(last<0,"display went blank after the first presented frame");++r.blank;require(r.blank<6,"demo never presented a frame");continue; }
    ++r.shown;
    // A transport frame must be exactly one completed frame: the previous
    // one again, or the next. Anything else is a torn or skipped frame.
    if(last>=0 && image==expected(unsigned(last))) { ++r.repeated;continue; }
    // The first swap happens before the display is enabled, so the first
    // visible frame may legitimately be the second one drawn.
    if(last<0 && image==expected(1)) last=0;
    const Image &next=expected(unsigned(last+1));
    for(unsigned i=0;i<image.size();++i) if(image[i]!=next[i])
      throw std::runtime_error("displayed frame "+std::to_string(r.shown)+" is not complete frame "+std::to_string(last+1)+
        " (torn, skipped or wrong pixels): first difference at x="+std::to_string(i%320)+" y="+std::to_string(i/320)+
        ", shown "+std::to_string(image[i])+", expected "+std::to_string(next[i]));
    ++last;++r.distinct;
  }
  for(unsigned i=0;i<64;++i) require(blit_byte(m.memory.memory,0x4000+i)==sprite[i],"CPU-uploaded sprite differs in physical memory");
  require(m.vsync_periods>=wanted,"vertical timing was not observed");
  if(preview) {
    std::ofstream out(preview,std::ios::binary);out<<"P6\n320 204\n255\n";
    for(const auto pixel:expected(unsigned(last))) for(int shift:{8,4,0}) out.put(char(((pixel>>shift)&15)*17));
    require(bool(out),"preview failed");
  }
  r.cycles=m.system_cycles;
  return r;
}
// Negative ROM: it draws into the displayed surface from its fourth frame.
static uint64_t run_bad_owner() {
  Machine m(39683,7001,8,0);
  m.allow_ownership_fault=true;
  const uint64_t deadline=m.system_cycles+16000000;
  while(!(m.dut.ownership_fault && m.dut.diagnostic==0xe0) && m.system_cycles<deadline) m.step();
  require(m.dut.ownership_fault,"write into the displayed surface was not detected");
  require(m.dut.diagnostic==0xe0,"CPU did not observe the ownership fault");
  return m.system_cycles;
}
int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);
    if(argc>1 && std::string(argv[1])=="--bad-owner") {
      const auto cycles=run_bad_owner();
      std::cout<<"PASS: ownership fault detected and reported to the CPU after "<<cycles<<" system cycles\n";
      return 0;
    }
    // 25.2 MHz nominal with an 8 MHz CPU, then a slower pixel clock and a
    // 64/6 MHz CPU at another phase.
    const Result a=run_demo(39683,7001,8,0,8,"enhanced-demo.ppm");
    const Result b=run_demo(39841,123,6,2,6,nullptr);
    for(const Result &r:{a,b}) require(r.repeated<=1,"demo did not sustain one new frame per transport frame");
    if(argc>1) {
      std::ofstream out(argv[1]);
      out<<"{\n  \"scope\": \"actual pinned R65C02 runs the demo ROM on the enhanced system skeleton: block-RAM memory, MMIO blitter, video control, native scanout and one shared SDRAM service against unchanged pin/pixel models; digital simulation only, no compositor, audio, input or physical test\",\n"
         <<"  \"clock_configurations\": 2,\n  \"complete_frames_checked\": "<<a.shown+b.shown
         <<",\n  \"distinct_frames\": "<<a.distinct+b.distinct<<",\n  \"repeated_frames\": "<<a.repeated+b.repeated
         <<",\n  \"blank_frames_before_first_present\": "<<a.blank+b.blank
         <<",\n  \"system_cycles\": "<<a.cycles+b.cycles
         <<",\n  \"torn_frames\": 0,\n  \"underruns\": 0,\n  \"ownership_faults\": 0,\n  \"physical_testing\": false,\n  \"passed\": true\n}\n";
      require(bool(out),"could not record evidence");
    }
    std::cout<<"PASS: CPU-drawn frames presented whole through native scanout, "<<a.distinct+b.distinct<<" distinct frames, "
             <<a.repeated+b.repeated<<" repeats, exact 2x canvas, no underrun or ownership fault, two clock configurations\n";
    return 0;
  } catch(const std::exception &e) { std::cerr<<"FAIL: "<<e.what()<<"\n";return 1; }
}
