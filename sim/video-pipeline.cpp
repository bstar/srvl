// Independent source patterns, contending memory client, physical-command SDRAM
// model and two unrelated clock phases. No production state is forced/read.
#include "Vtang_video_top.h"
#include "verilated.h"
#include "sdram-model.hpp"
#include <array>
#include <fstream>
#include <iostream>
#include <optional>
#include <set>

static void require(bool ok,const std::string &why) { if(!ok) throw std::runtime_error(why); }
static uint16_t pattern(unsigned frame,unsigned x,unsigned y) {
  return uint16_t((((x+frame*3)&15)<<8)|(((y+frame*5)&15)<<4)|((x/16+y/16+frame)&15));
}
class Pipeline {
  uint64_t now=0,next_video=73;
  unsigned video_half=320;
  uint32_t host_sequence=0;
  bool host_pending=false, host_expected_write=false;
  uint32_t host_expected=0;
  unsigned source_frame=0,source_address=0,source_gap=0;
  std::optional<unsigned> canvas_id;
  unsigned canvas_pixels=0;
  bool canvas_started=false, canvas_active=false;
  bool row_blank=false;
  std::set<unsigned> allowed;
  std::array<uint64_t,4> stalled_request{};
  bool was_stalled=false;
  uint64_t pixel_clocks=0;
  unsigned last_x=0,last_y=0;
  bool have_pixel=false;
public:
  Vtang_video_top dut;
  SdramModel memory;
  uint64_t cycles=0,host_accepted=0,host_completed=0,host_cancelled=0,canvas_frames=0;
  unsigned latest_frame=0;
  bool check_underruns=true, allow_blank_rows=false, generate_host=true;
  explicit Pipeline(unsigned half=320):video_half(half) {
    dut.clk=0; dut.reset=1; dut.video_clk=0; dut.video_reset=1; dut.enable=1;
    dut.memory_stall=0; dut.pixel_write=0; dut.pixel_address=0; dut.pixel_data=0;
    dut.host_valid=0; dut.host_write=0; dut.host_address=0; dut.host_data=0; dut.host_mask=15; dut.dq_in=0;
    dut.eval(); dut.clk=1; dut.eval();
  }
  void pixels() {
    if(dut.video_reset) { have_pixel=false; canvas_started=false; return; }
    const unsigned x=dut.video_x,y=dut.video_y;
    if(have_pixel) require((x==(last_x==799?0:last_x+1)) && y==(last_x==799?(last_y==524?0:last_y+1):last_y),"video timing skipped/duplicated a position");
    last_x=x; last_y=y; have_pixel=true; ++pixel_clocks;
    require(bool(dut.video_de)==(x<640 && y<480),"DE does not match 640x480");
    require(bool(dut.video_hsync)==!(x>=656 && x<752),"horizontal sync width/polarity mismatch");
    require(bool(dut.video_vsync)==!(y>=490 && y<492),"vertical sync width/polarity mismatch");
    const bool inside=x>=160 && x<480 && y>=138 && y<342;
    if(!inside) { require(dut.video_rgb==0,"nonblack border or blanking"); return; }
    const unsigned sx=(x-160)/2,sy=(y-138)/2;
    if(x==160 && y==138) {
      canvas_id.reset(); canvas_pixels=0; canvas_started=true;
      canvas_active=dut.video_frame_valid;
      if(canvas_active) {
        for(unsigned id:allowed) if(pattern(id,0,0)==dut.video_rgb) canvas_id=id;
        require(canvas_id.has_value(),"display started an unknown/incomplete source frame");
      }
    }
    if(!canvas_started) return;
    if(canvas_active) {
      const uint16_t expected=pattern(*canvas_id,sx,sy);
      if(x==160 && ((y-138)&1)==0) row_blank=allow_blank_rows && dut.video_rgb==0;
      require(dut.video_rgb==(row_blank?0:expected),"scaled pixel differs or underrun exposed a partial row at "+std::to_string(x)+","+std::to_string(y)+" got "+std::to_string(dut.video_rgb)+" expected "+std::to_string(row_blank?0:expected));
      ++canvas_pixels;
    } else require(dut.video_rgb==0,"frame became visible midway through the canvas");
    if(x==479 && y==341 && canvas_active) {
      require(canvas_pixels==320*204,"scaled frame pixel count wrong");
      ++canvas_frames; latest_frame=*canvas_id;
      std::cout<<"PASS: complete 320x204 canvas from source frame "<<latest_frame<<", pixel half-period "<<video_half<<"\n";
      canvas_started=false;
    }
  }
  void advance(uint64_t target) {
    while(next_video<target) {
      dut.video_clk=!dut.video_clk; dut.eval();
      if(dut.video_clk) pixels();
      next_video+=video_half;
    }
    now=target;
  }
  void source() {
    dut.pixel_write=0;
    if(!source_frame) return;
    if(source_gap) { --source_gap; return; }
    dut.pixel_write=1; dut.pixel_address=source_address;
    dut.pixel_data=pattern(source_frame,source_address%160,source_address/160);
    ++source_address;
    source_gap=3;
    if(source_address%160==0) source_gap+=4000;
    if(source_address==16320) { source_frame=0; source_address=0; }
  }
  void tick() {
    if(!dut.reset) {
      source();
      if(generate_host && !host_pending) {
        dut.host_valid=1; dut.host_write=(host_sequence&1)==0;
        dut.host_address=0x2000+((host_sequence/2)%256)*4;
        dut.host_data=0x31504c59u ^ (host_sequence/2)*0x9e3779b9u;
      } else dut.host_valid=0;
    }
    advance(now+126);
    dut.clk=0; dut.dq_in=memory.dq(); dut.eval();
    memory.edge({bool(dut.sdram_cke),bool(dut.sdram_cs_n),bool(dut.sdram_ras_n),bool(dut.sdram_cas_n),bool(dut.sdram_we_n),bool(dut.dq_oe),uint16_t(dut.sdram_a),uint8_t(dut.sdram_ba),uint8_t(dut.sdram_dqm),uint32_t(dut.dq_out)});
    dut.dq_in=memory.dq(); dut.eval();
    advance(now+126);
    if(!dut.reset) {
      if(dut.host_response) {
        require(host_pending,"unowned host response");
        if(!host_expected_write) require(dut.host_read_data==host_expected,"arbiter routed incorrect host read data");
        host_pending=false; ++host_sequence; ++host_completed;
      }
      if(dut.host_valid && dut.host_ready) {
        require(!host_pending,"host request accepted twice");
        host_pending=true; host_expected_write=dut.host_write;
        host_expected=0x31504c59u ^ (host_sequence/2)*0x9e3779b9u;
        ++host_accepted;
      }
      const std::array<uint64_t,4> request{dut.memory_address,dut.memory_data,dut.memory_mask,dut.memory_write};
      if(was_stalled) require(dut.memory_valid && request==stalled_request,"memory request changed under backpressure");
      was_stalled=dut.memory_valid && !dut.memory_ready;
      stalled_request=request;
      if(dut.memory_valid && dut.memory_ready && dut.memory_address>=0x100000) {
        const unsigned bank=(dut.memory_address-0x100000)>>16;
        require(bank<3 && (dut.memory_address&65535)<32640,"video access outside reserved frame storage");
        if(dut.memory_write) require(!dut.display_valid || bank!=dut.display_bank,"write into displayed frame");
        else require(dut.display_valid && bank==dut.display_bank,"scanout read an unowned bank");
      }
    }
    dut.clk=1; dut.eval(); ++cycles;
    require(!dut.capture_fault && !dut.scan_fault && !dut.arbiter_fault,"video/memory ownership protocol fault");
    if(check_underruns) require(!dut.underrun_count,"unexpected scanout underrun");
  }
  void idle(uint64_t clocks) { while(clocks--) tick(); }
  void frame(unsigned id,bool display_allowed=true) {
    require(!source_frame,"source frame overlap");
    if(display_allowed) allowed.insert(id);
    source_frame=id;
    while(source_frame) tick();
  }
  void await(unsigned id) {
    for(unsigned n=0;latest_frame!=id && n<4500000;++n) tick();
    require(latest_frame==id,"requested source frame never presented");
  }
  void reset() { idle(8); dut.reset=0; dut.video_reset=0; idle(13000); }
  void hard_reset() {
    if(host_pending) ++host_cancelled;
    host_pending=false; host_sequence=0; was_stalled=false;
    source_frame=0; source_address=0; source_gap=0;
    latest_frame=0; allowed.clear();
    dut.reset=1; dut.video_reset=1; dut.pixel_write=0; dut.host_valid=0; dut.memory_stall=0;
    memory.expect_initialization();
    reset();
  }
};
int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);
    Pipeline p; p.reset();
    p.frame(1); p.await(1);
    const auto first=p.canvas_frames;
    while(p.canvas_frames<first+2) p.tick(); // Repeat a complete frame.
    p.frame(2); p.frame(3); p.frame(4); p.await(4); // Source faster than presentation.
    require(!p.dut.overflow && !p.dut.dropped_frames,"normal capture unexpectedly dropped/overflowed");
    require(p.host_completed>10000,"insufficient simultaneous third-client contention");
    p.generate_host=false;
    p.idle(100);
    require(p.host_accepted==p.host_completed,"host request lost under contention");
    const uint64_t good_frames=p.canvas_frames;
    // Deliberately miss line deadlines. A late ACK must not expose half a row.
    p.check_underruns=false; p.allow_blank_rows=true;
    while(!(p.dut.video_y==160 && p.dut.video_x==0)) p.tick();
    p.dut.memory_stall=1; p.idle(20000); p.dut.memory_stall=0;
    p.idle(1500000);
    require(p.dut.underrun_count!=0,"withheld memory did not report a missed display deadline");
    // The count is sticky; require fully correct recovered pixels separately.
    const auto before_recovery=p.canvas_frames;
    while(p.canvas_frames<before_recovery+1) p.tick();
    p.allow_blank_rows=false;
    while(p.canvas_frames<before_recovery+3) p.tick();
    // Overflow a source frame while an older complete image is displayed.
    // Deliberately exclude this pattern from the allowed presentation set.
    p.allow_blank_rows=true; p.dut.memory_stall=1;
    p.frame(7,false); p.idle(100); p.dut.memory_stall=0; p.idle(1500000);
    require(p.dut.overflow && p.dut.dropped_frames==1,"capture overflow did not invalidate exactly one candidate");
    const auto after_overflow=p.canvas_frames;
    while(p.canvas_frames<after_overflow+1) p.tick();
    p.allow_blank_rows=false;
    while(p.canvas_frames<after_overflow+2) p.tick();
    require(p.latest_frame==4,"invalidated overflow frame replaced the displayed frame");

    Pipeline q(318); q.reset(); // Different frequency and phase progression.
    q.frame(5); q.await(5); q.frame(6); q.await(6);
    require(!q.dut.overflow,"capture overflow at second pixel-clock ratio");
    q.dut.memory_stall=1; q.idle(32);
    require(q.dut.memory_valid,"reset test did not block an actual outstanding request");
    q.hard_reset(); q.frame(8); q.await(8);
    q.generate_host=false; q.idle(100);
    require(q.host_accepted==q.host_completed+q.host_cancelled,"reset lost an unaccounted host request");
    require(!q.dut.overflow && !q.dut.underrun_count,"hard-reset recovery retained stale video fault/ownership");
    std::cout<<"PASS: video pipeline, "<<good_frames<<" clean primary frames, "<<p.host_completed
             <<" completed contending requests, "<<p.memory.refresh_count<<" refreshes, "
             <<p.dut.underrun_count<<" intentionally missed row-pair deadlines; independent clock ratio also passed\n";
    if(argc==2) {
      std::ofstream evidence(argv[1]);
      evidence<<"{\n  \"scope\": \"patterned capture, round-robin contention, command-modeled SDRAM and dual-clock RGB scanout\",\n"
              <<"  \"cycles\": "<<p.cycles+q.cycles<<",\n  \"scaled_canvas_pixels\": 65280,\n"
              <<"  \"clean_primary_frames_before_injected_faults\": "<<good_frames<<",\n"
              <<"  \"host_completed\": "<<p.host_completed+q.host_completed<<",\n"
              <<"  \"reset_cancelled_host_requests\": "<<q.host_cancelled<<",\n"
              <<"  \"refreshes\": "<<p.memory.refresh_count+q.memory.refresh_count<<",\n"
              <<"  \"max_refresh_gap\": "<<std::max(p.memory.max_refresh_gap,q.memory.max_refresh_gap)<<",\n"
              <<"  \"deliberate_underrun_row_pairs\": "<<p.dut.underrun_count<<",\n"
              <<"  \"invalidated_overflow_frames\": "<<p.dut.dropped_frames<<",\n"
              <<"  \"pixel_half_period_units\": [320,318],\n  \"sys_half_period_units\": 126,\n"
              <<"  \"physical_testing\": false,\n  \"board_timing_signoff\": false,\n  \"passed\": true\n}\n";
    }
    return 0;
  } catch(const std::exception &error) { std::cerr<<"FAIL: "<<error.what()<<"\n"; return 1; }
}
