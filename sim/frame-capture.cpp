// Verify committed frame ownership against an independently delayed write sink.
// This is a same-clock capture/presentation-token test, not video scanout/CDC.
#include "Vlynx_frame_capture.h"
#include "verilated.h"
#include <array>
#include <iostream>
#include <optional>
#include <random>
#include <set>
#include <stdexcept>

static constexpr unsigned pixels=16320;
static uint16_t color(unsigned frame,unsigned address) { return (frame*97+address*17)&4095; }
static void require(bool ok,const char *message) { if(!ok) throw std::runtime_error(message); }
class Frames {
  struct Write { unsigned bank,index; uint16_t value; uint64_t due; };
  std::optional<Write> pending;
  std::array<std::array<uint16_t,pixels>,3> memory{};
  std::array<unsigned,3> next_address{};
  std::mt19937 random{0x320204};
  std::set<unsigned> known_frames;
  bool previous_ready=false;
  int previous_display=-1;
public:
  Vlynx_frame_capture dut;
  uint64_t cycles=0,accepted=0,completed=0,presentations=0;
  unsigned last_committed_index=0,last_committed_frame=0,displayed_frame=0;
  bool stall=false;
  Frames() {
    dut.clk=0; dut.reset=1; dut.enable=1; dut.pixel_write=0;
    dut.pixel_address=0; dut.pixel_data=0; dut.present=0;
    dut.write_ready=0; dut.write_response=0;
  }
  unsigned identify(unsigned bank) const {
    for(unsigned id:known_frames) {
      bool match=true;
      for(unsigned n=0;n<pixels;++n) if(memory[bank][n]!=color(id,n)) { match=false; break; }
      if(match) return id;
    }
    return 0;
  }
  void tick() {
    dut.write_response=0;
    if(dut.reset) { pending.reset(); previous_ready=false; previous_display=-1; }
    else if(pending && pending->due<=cycles) {
      const Write w=*pending;
      require(!dut.display_valid || dut.display_bank!=w.bank,"write committed into the displayed frame");
      memory[w.bank][w.index]=w.value; ++completed;
      last_committed_index=w.index;
      // Infer the source identity from pixel zero; all RGB samples are checked
      // independently again when a bank becomes visible.
      last_committed_frame=0;
      for(unsigned id:known_frames) if(memory[w.bank][0]==color(id,0)) last_committed_frame=id;
      pending.reset(); dut.write_response=1;
    }
    dut.write_ready=!stall && !pending && (random()%4!=0);
    dut.clk=0; dut.eval();
    if(!dut.reset && dut.write_valid && dut.write_ready) {
      require(!pending,"capture issued two outstanding writes");
      require(dut.write_address>=0x100000 && dut.write_address<0x130000,"capture wrote outside its reserved frame banks");
      const unsigned relative=dut.write_address-0x100000;
      const unsigned bank=relative>>16, index=(relative&65535)>>1;
      require(index<pixels && !(relative&1),"capture pixel address is outside a frame");
      require(!dut.display_valid || dut.display_bank!=bank,"capture overwrites a displayed bank");
      require(dut.write_mask==((index&1)?12:3),"pixel half-word mask incorrect");
      const unsigned value=(dut.write_data>>((index&1)*16))&65535;
      require(value<4096,"RGB444 padding bits changed");
      if(index==0) next_address[bank]=0;
      require(index==next_address[bank]++,"FIFO lost/duplicated/reordered a bank's pixel writes");
      pending=Write{bank,index,uint16_t(value),cycles+3+random()%13}; ++accepted;
    }
    dut.clk=1; dut.eval(); ++cycles;
    if(!dut.reset) {
      if(dut.frame_ready && !previous_ready) {
        bool complete=false;
        for(unsigned bank=0;bank<3;++bank) complete|=identify(bank)!=0;
        require(complete,"frame announced before all pixels committed");
      }
      if(dut.display_valid && int(dut.display_bank)!=previous_display) {
        displayed_frame=identify(dut.display_bank);
        require(displayed_frame!=0,"presented a partial/mixed/unrecognized frame");
        ++presentations; previous_display=dut.display_bank;
      }
      previous_ready=dut.frame_ready;
    }
  }
  void idle(unsigned n) { dut.pixel_write=0; while(n--) tick(); }
  void reset() { dut.reset=1; idle(4); dut.reset=0; idle(4); }
  void pixel(unsigned frame,unsigned address) {
    dut.pixel_write=1; dut.pixel_address=address; dut.pixel_data=color(frame,address); tick();
  }
  void emit(unsigned frame,bool last_gap=true) {
    known_frames.insert(frame);
    for(unsigned n=0;n<pixels;++n) {
      pixel(frame,n); idle(3);
      if(n%160==159 && (last_gap || n+1!=pixels)) idle(4000);
    }
  }
  void present() { dut.present=1; idle(1); dut.present=0; }
  void allow(unsigned id) { known_frames.insert(id); }
};
int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);
    Frames f; f.reset();
    f.emit(1); require(f.dut.frame_ready && !f.dut.display_valid,"first complete frame readiness incorrect");
    f.emit(2,false);
    for(unsigned n=0;n<20000 && !(f.last_committed_frame==2 && f.last_committed_index==pixels-1);++n) f.idle(1);
    require(f.last_committed_frame==2 && f.last_committed_index==pixels-1,"second frame never committed");
    // The next edge retires B while presenting the previously ready A.
    f.present(); require(f.displayed_frame==1 && f.dut.frame_ready,"simultaneous present/retire lost a completed frame");
    f.present(); require(f.displayed_frame==2 && !f.dut.frame_ready,"second frame handoff failed");
    require(!f.dut.overflow && !f.dut.capture_error,"normal burst capture signaled an error");

    // Withhold every write, fill the queue, then drain an invalidated frame.
    f.reset(); f.stall=true;
    for(unsigned n=0;n<pixels;++n) f.pixel(3,n);
    f.idle(2); require(f.dut.overflow && f.dut.dropped_frames==1,"overflow did not invalidate the whole frame");
    f.stall=false; f.idle(20000);
    require(!f.dut.frame_ready && !f.dut.display_valid,"partly written overflow frame became visible");
    f.emit(4); f.present(); require(f.displayed_frame==4,"capture did not recover after overflow");

    // Interrupt one candidate with a new frame; keep the old display immutable.
    f.allow(5);
    for(unsigned n=0;n<100;++n) { f.pixel(5,n); f.idle(30); }
    f.emit(6); f.present();
    require(f.displayed_frame==6 && f.dut.capture_error && f.dut.dropped_frames>=2,"truncated candidate handling failed");
    // A discontinuous address invalidates another candidate, never the display.
    f.pixel(7,0); f.idle(20); f.pixel(7,2); f.idle(20000);
    require(!f.dut.frame_ready && f.displayed_frame==6,"out-of-order source frame became ready");
    // Disabling capture drains, rather than prematurely reusing, queued writes.
    for(unsigned n=0;n<80;++n) f.pixel(8,n);
    f.dut.enable=0; f.idle(20000); f.dut.enable=1;
    require(!f.dut.frame_ready && f.displayed_frame==6,"disabled partial capture became ready");
    f.emit(9); f.present(); require(f.displayed_frame==9,"bank reuse after disable did not recover");
    f.idle(20000);
    require(f.accepted==f.completed,"outstanding frame write was lost");
    std::cout<<"PASS: RGB444 capture with delayed ACKs, "<<f.accepted<<" committed pixel writes, "<<f.presentations
             <<" valid presentations; simultaneous handoff, overflow, truncation, order, disable/drain and bank reuse\n";
    f.dut.final(); return 0;
  } catch(const std::exception &error) { std::cerr<<"FAIL: "<<error.what()<<"\n"; return 1; }
}
