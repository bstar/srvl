// Real arbiter/controller plus an independent SDRAM command model. Commands and
// assets are test stimulus, not CPU firmware; peer reads are synthetic traffic.
#include "Venhanced_blitter_memory_top.h"
#include "verilated.h"
#include "sdram-model.hpp"
#include "scaled-blitter-model.hpp"
#include <array>
#include <fstream>
#include <iostream>
#include <optional>
#include <stdexcept>

static void require(bool ok,const std::string &why) { if(!ok) throw std::runtime_error(why); }
class System {
  bool host_pending=false,peer_pending=false,host_was_write=false;
  bool manual_host=false;
  uint32_t host_saved_address=0,host_saved_data=0,host_expected=0,peer_expected=0;
  unsigned host_saved_mask=0;
  uint64_t peer_next=0,peer_release=0,peer_sequence=0;
  uint32_t host_sequence=0;
  std::optional<std::array<uint64_t,4>> held;
public:
  Venhanced_blitter_memory_top dut;
  SdramModel memory;
  std::vector<uint32_t> expected=memory.memory;
  uint64_t cycles=0,host_accepted=0,host_completed=0,host_cancelled=0,peer_accepted=0,peer_completed=0,peer_cancelled=0;
  uint64_t engine_reads=0,engine_writes=0,engine_completions=0,engine_cancelled=0,max_peer_response_from_release=0;
  uint64_t commands=0,samples=0,pixels=0,command_cycles=0,memory_stalls=0;
  bool host_load=false,peer_load=false;
  System() {
    dut.clk=0;dut.reset=1;dut.command_valid=0;dut.completion_ready=0;dut.dq_in=0;dut.memory_stall=0;
    dut.host_valid=0;dut.host_write=0;dut.host_address=0;dut.host_data=0;dut.host_mask=15;
    dut.peer_valid=0;dut.peer_address=0;drive_blit(dut,BlitCommand{});
    dut.eval();dut.clk=1;dut.eval();reset();
  }
  void tick() {
    if(!dut.reset) {
      if(!manual_host) {
        dut.host_valid=(host_load || dut.host_valid) && !host_pending;
        if(dut.host_valid) {
          dut.host_write=(host_sequence%2)==0;dut.host_address=0x100000+((host_sequence/2)%256)*4;
          dut.host_data=0x2468ace0u^(host_sequence/2)*0x9e3779b9u;dut.host_mask=15;
        }
      }
      dut.peer_valid=((peer_load && cycles>=peer_next) || dut.peer_valid) && !peer_pending;
      if(dut.peer_valid) dut.peer_address=0x200000+uint32_t(peer_sequence%32640)*4;
    }
    dut.clk=0;dut.dq_in=memory.dq();dut.eval();
    memory.edge({bool(dut.sdram_cke),bool(dut.sdram_cs_n),bool(dut.sdram_ras_n),bool(dut.sdram_cas_n),bool(dut.sdram_we_n),bool(dut.dq_oe),
                 uint16_t(dut.sdram_a),uint8_t(dut.sdram_ba),uint8_t(dut.sdram_dqm),uint32_t(dut.dq_out)});
    dut.dq_in=memory.dq();dut.eval();
    if(!dut.reset) {
      if(dut.host_response) {
        require(host_pending,"unowned host response");
        if(host_was_write) {
          for(unsigned lane=0;lane<4;++lane) if(host_saved_mask&(1u<<lane))
            blit_byte(expected,host_saved_address+lane,uint8_t(host_saved_data>>(8*lane)));
        }
        if(!host_was_write) require(dut.host_read_data==host_expected,"host read data lost/corrupted under drawing contention");
        host_pending=false;++host_completed;++host_sequence;
      }
      if(dut.host_valid && dut.host_ready) {
        require(!host_pending,"host accepted twice");host_pending=true;
        host_was_write=dut.host_write;host_saved_address=dut.host_address;host_saved_data=dut.host_data;host_saved_mask=dut.host_mask;
        host_expected=expected.at(dut.host_address/4);++host_accepted;
      }
      if(dut.peer_response) {
        require(peer_pending,"unowned front-read response");
        require(dut.peer_read_data==peer_expected,"front-surface read changed during back-surface drawing");
        max_peer_response_from_release=std::max(max_peer_response_from_release,cycles-peer_release);
        peer_pending=false;++peer_completed;
      }
      if(dut.peer_valid && dut.peer_ready) {
        require(!peer_pending,"peer accepted twice");peer_pending=true;
        peer_expected=expected.at(dut.peer_address/4);peer_release=peer_next;peer_next+=32;
        ++peer_accepted;++peer_sequence;
      }
      const std::array<uint64_t,4> request{dut.memory_write,dut.memory_address,dut.memory_data,dut.memory_mask};
      if(held) require(dut.memory_valid && request==*held,"blitter request changed under arbiter backpressure");
      held=dut.memory_valid && !dut.memory_ready ? std::optional(request):std::nullopt;
      if(dut.memory_valid && dut.memory_ready) {
        if(dut.memory_write) ++engine_writes;else ++engine_reads;
      }
      if(dut.memory_response) ++engine_completions;
    }
    dut.clk=1;dut.eval();++cycles;
    require(!dut.protocol_fault && !dut.arbiter_fault,"engine/arbiter protocol fault");
  }
  void idle(uint64_t count) { while(count--) tick(); }
  void reset() {
    const auto outstanding=engine_reads+engine_writes-engine_completions-engine_cancelled;
    require(outstanding<=1,"multiple blitter requests outstanding at reset");engine_cancelled+=outstanding;
    host_load=peer_load=false;manual_host=false;dut.host_valid=0;dut.peer_valid=0;dut.command_valid=0;
    if(host_pending) ++host_cancelled;
    if(peer_pending) ++peer_cancelled;
    host_pending=peer_pending=false;held.reset();dut.reset=1;memory.expect_initialization();idle(3);
    dut.reset=0;const auto deadline=cycles+14000;
    while(!dut.initialized && cycles<deadline) tick();
    require(dut.initialized && dut.command_ready && !dut.completion_valid,"reset/SDRAM initialization did not complete");
    // Reset does not roll back writes already committed by the physical memory.
    expected=memory.memory;host_sequence=0;peer_next=cycles;peer_sequence=0;
  }
  void transfer(uint32_t address,uint32_t data) {
    require(!host_pending && !host_load,"manual upload overlaps automatic host work");
    manual_host=true;dut.host_valid=1;dut.host_write=1;dut.host_address=address;dut.host_data=data;dut.host_mask=15;
    const auto accepted=host_accepted,complete=host_completed,deadline=cycles+10000;
    while(host_accepted==accepted && cycles<deadline) tick();
    require(host_accepted!=accepted,"host upload acceptance timeout");dut.host_valid=0;
    while(host_completed==complete && cycles<deadline) tick();
    require(host_completed!=complete,"host upload completion timeout");manual_host=false;
  }
  void upload(const BlitCommand &c) {
    auto staged=expected;
    for(unsigned y=0;y<c.source_height;++y) for(unsigned x=0;x<c.source_width;++x) {
      const unsigned value=((x/3+y/3)%5==0) ? 0:1+(x*3+y*5)%unsigned(c.bpp4?15:255);
      const auto address=c.source+y*c.source_stride+(c.bpp4?x/2:x);
      if(c.bpp4) {
        const unsigned shift=4*(x%2);
        blit_byte(staged,address,uint8_t((blit_byte(staged,address)&~(15u<<shift))|(value<<shift)));
      } else blit_byte(staged,address,uint8_t(value));
    }
    const uint32_t end=c.source+(c.source_height-1)*c.source_stride+(c.bpp4?(c.source_width+1)/2:c.source_width);
    for(uint32_t address=c.source&~3u;address<end;address+=4) transfer(address,staged.at(address/4));
  }
  void loads(bool host,bool peer,unsigned front_release_offset=0) {
    host_load=host;peer_load=peer;peer_next=cycles+front_release_offset;
  }
  void drain() {
    host_load=peer_load=false;const auto deadline=cycles+10000;
    while((host_pending || peer_pending || dut.host_valid || dut.peer_valid) && cycles<deadline) tick();
    require(!host_pending && !peer_pending,"background memory requests did not drain");
    require(memory.memory==expected,"physical SDRAM contents differ from independent pixel/host reference");
  }
  void draw(BlitCommand c) {
    c.tag=uint16_t(++commands);const auto result=blit_reference(expected,c);
    const auto first=cycles,reads=engine_reads,writes=engine_writes;
    require(dut.command_ready,"command submitted while renderer busy");
    drive_blit(dut,c);dut.command_valid=1;tick();dut.command_valid=0;
    BlitCommand junk;junk.width=0;junk.source=0x7fffff;drive_blit(dut,junk);
    const auto deadline=cycles+10000000;
    while(!dut.completion_valid && cycles<deadline) tick();
    require(dut.completion_valid,"draw/fill timed out under SDRAM contention");
    require(dut.completion_tag==c.tag && dut.completion_error==result.error,"incorrect draw completion");
    require(dut.sampled_pixels==result.samples && dut.written_pixels==result.pixels,"sample/pixel counters differ");
    require(dut.read_requests==engine_reads-reads && dut.write_requests==engine_writes-writes,"engine transaction counters differ");
    require(dut.command_cycles==cycles-first,"draw cycle accounting wrong");
    samples+=result.samples;pixels+=result.pixels;command_cycles+=dut.command_cycles;memory_stalls+=dut.memory_stalls;
    dut.completion_ready=1;tick();dut.completion_ready=0;
  }
  void preview(const char *path,uint32_t base) const {
    std::ofstream image(path,std::ios::binary);image<<"P6\n320 204\n255\n";
    for(unsigned y=0;y<204;++y) for(unsigned x=0;x<320;++x) {
      const auto pixel=memory.memory.at((base+y*640+x*2)/4)>>(16*(x%2));
      const unsigned index=pixel&255;
      const std::array<uint8_t,3> rgb=index ? std::array<uint8_t,3>{uint8_t(45+(index*37)%200),uint8_t(40+(index*67)%205),uint8_t(35+(index*97)%210)}:std::array<uint8_t,3>{15,25,23};
      image.write(reinterpret_cast<const char *>(rgb.data()),3);
    }
    require(bool(image),"preview output failed");
  }
};
struct Scene { const char *name;uint64_t cycles,samples,pixels,reads,writes,peer_words,host_requests,stalls; };
int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);System m;BlitCommand small,packed,large;
    small.source=0x4003;small.source_stride=19;
    packed=small;packed.source=0x6001;packed.bpp4=true;packed.source_stride=11;
    large=small;large.source=0x8001;large.source_width=32;large.source_height=32;large.source_stride=37;
    m.upload(small);m.upload(packed);m.upload(large);m.drain();
    auto small_scene=[&](unsigned objects,unsigned front_release_offset) {
      m.loads(false,true,front_release_offset);const auto first=m.cycles,samples=m.samples,pixels=m.pixels,reads=m.engine_reads,writes=m.engine_writes,peer=m.peer_completed,host=m.host_accepted,stalls=m.memory_stalls;
      BlitCommand clear;clear.fill=true;clear.fill_covered=false;clear.width=320;clear.height=204;m.draw(clear);
      for(unsigned n=0;n<objects;++n) {
        auto c=(n%2)?packed:small;c.x=int((n*23)%304);c.y=int((n*37)%188);c.palette=uint8_t(n%15+1);c.band=uint8_t(n%16);
        c.flip_x=n%3==0;c.flip_y=n%5==0;m.draw(c);
      }
      const Scene scene{objects==64?"clear plus 64 small sprites":"clear plus 256 small sprites",m.cycles-first,m.samples-samples,m.pixels-pixels,m.engine_reads-reads,m.engine_writes-writes,m.peer_completed-peer,m.host_accepted-host,m.memory_stalls-stalls};
      m.drain();
      require(scene.cycles*60<=64000000,"small-sprite renderer workload regressed beyond its 60 Hz budget at assumed 64 MHz");
      return scene;
    };
    std::vector<Scene> scenes;
    for(unsigned objects:{64u,256u}) scenes.push_back(small_scene(objects,0));
    BlitCommand clear;clear.fill=true;clear.fill_covered=false;clear.width=320;clear.height=204;
    auto scaled_scene=[&](unsigned front_release_offset) {
      m.loads(true,true,front_release_offset);const auto first=m.cycles,samples=m.samples,pixels=m.pixels,reads=m.engine_reads,writes=m.engine_writes,peer=m.peer_completed,host=m.host_accepted,stalls=m.memory_stalls;
      m.draw(clear);
      for(unsigned n=0;n<32;++n) {
        auto c=large;c.x=int((n*71)%350)-30;c.y=int((n*43)%240)-20;c.width=20+(n*7)%60;c.height=16+(n*11)%55;
        c.flip_x=n%2;c.flip_y=n%3==0;c.band=uint8_t(n%16);m.draw(c);
      }
      const Scene scene{"clear plus 32 scaled sprites with host traffic",m.cycles-first,m.samples-samples,m.pixels-pixels,m.engine_reads-reads,m.engine_writes-writes,m.peer_completed-peer,m.host_accepted-host,m.memory_stalls-stalls};
      m.drain();
      require(scene.cycles*60<=64000000,"host-contended scaled renderer workload exceeded its 60 Hz budget at assumed 64 MHz");
      return scene;
    };
    scenes.push_back(scaled_scene(0));m.preview("scaled-scene.ppm",clear.destination);
    // The renderer-only dense budget must survive different front-read release
    // phases. These repeats do not weaken the original contended host workload.
    std::vector<std::pair<unsigned,uint64_t>> dense_phases;
    for(unsigned phase:{1u,7u,15u,31u}) {
      const auto scene=small_scene(256,phase);
      dense_phases.push_back({phase,scene.cycles});
    }
    std::vector<std::pair<unsigned,uint64_t>> scaled_phases;
    for(unsigned phase:{1u,7u,15u,31u}) {
      const auto scene=scaled_scene(phase);
      scaled_phases.push_back({phase,scene.cycles});
    }
    // Hold a real accepted write behind arbiter/controller backpressure, reset,
    // reinitialize SDRAM, then prove fresh work completes with no stale fence.
    const auto writes_before_reset=m.engine_writes;
    m.dut.memory_stall=1;drive_blit(m.dut,clear);m.dut.command_valid=1;m.tick();m.dut.command_valid=0;
    const auto deadline=m.cycles+10000;
    while(m.engine_writes==writes_before_reset && m.cycles<deadline) m.tick();
    require(m.cycles<deadline,"could not reach contended reset case");
    m.idle(900);require(!m.dut.completion_valid,"held write completed before downstream service");
    m.dut.memory_stall=0;m.reset();m.draw(clear);m.draw(small);m.drain();
    auto partial=clear;partial.width=2;partial.height=1;partial.fill_index=0x77;partial.fill_covered=true;
    auto physical=m.memory.write_count;drive_blit(m.dut,partial);m.dut.command_valid=1;m.tick();m.dut.command_valid=0;
    const auto write_deadline=m.cycles+10000;
    while(m.memory.write_count==physical && m.cycles<write_deadline) m.tick();
    require(m.cycles<write_deadline && !m.dut.completion_valid,"could not reset after physical write but before its fence");
    require(m.memory.memory.at(partial.destination/4)==0x10771077,"physical write had incorrect filled pixels");
    m.reset();require(m.memory.memory.at(partial.destination/4)==0x10771077,"logic reset incorrectly rolled back committed SDRAM data");
    m.draw(clear);m.draw(small);m.drain();
    physical=m.memory.read_count;drive_blit(m.dut,small);m.dut.command_valid=1;m.tick();m.dut.command_valid=0;
    const auto read_deadline=m.cycles+10000;
    while(m.memory.read_count==physical && m.cycles<read_deadline) m.tick();
    require(m.cycles<read_deadline && !m.dut.completion_valid,"could not reset with physical read in flight");
    m.reset();m.draw(clear);m.draw(small);m.drain();
    require(m.host_accepted==m.host_completed+m.host_cancelled && m.peer_accepted==m.peer_completed+m.peer_cancelled,"background transaction accounting wrong");
    require(m.engine_reads+m.engine_writes==m.engine_completions+m.engine_cancelled,"blitter transaction accounting wrong");
    if(argc>1) {
      std::ofstream out(argv[1]);
      out<<"{\n  \"scope\": \"scaled-blitter plus actual arbiter/SDRAM RTL against independent physical-command and pixel models; host commands and synthetic front reads, no CPU/native scanout\",\n"
         <<"  \"commands\": "<<m.commands<<",\n  \"sampled_pixels\": "<<m.samples<<",\n  \"written_pixels\": "<<m.pixels
         <<",\n  \"refreshes\": "<<m.memory.refresh_count<<",\n  \"max_refresh_gap_cycles\": "<<m.memory.max_refresh_gap
         <<",\n  \"max_peer_response_from_release_cycles\": "<<m.max_peer_response_from_release
         <<",\n  \"engine_accepted_transactions\": "<<m.engine_reads+m.engine_writes<<",\n  \"engine_completed_transactions\": "<<m.engine_completions
         <<",\n  \"engine_reset_cancelled_transactions\": "<<m.engine_cancelled
         <<",\n  \"reset_after_committed_write\": true,\n  \"reset_with_physical_read_in_flight\": true,\n  \"assumed_system_hz\": 64000000,\n  \"scenes\": [\n";
      for(size_t n=0;n<scenes.size();++n) {
        const auto &s=scenes[n];
        out<<"    {\"name\": \""<<s.name<<"\", \"cycles\": "<<s.cycles<<", \"sampled_pixels\": "<<s.samples<<", \"written_pixels\": "<<s.pixels
           <<", \"reads\": "<<s.reads<<", \"writes\": "<<s.writes<<", \"peer_read_words\": "<<s.peer_words<<", \"host_requests\": "<<s.host_requests
           <<", \"memory_stall_cycles\": "<<s.stalls<<", \"within_60hz_frame_at_assumed_clock\": "<<(s.cycles*60<=64000000?"true":"false")<<"}"<<(n+1<scenes.size()?",":"")<<"\n";
      }
      out<<"  ],\n  \"dense_front_release_phase_sweeps\": [\n";
      for(size_t n=0;n<dense_phases.size();++n)
        out<<"    {\"offset_cycles\": "<<dense_phases[n].first<<", \"cycles\": "<<dense_phases[n].second<<"}"
           <<(n+1<dense_phases.size()?",":"")<<"\n";
      out<<"  ],\n  \"scaled_host_front_release_phase_sweeps\": [\n";
      for(size_t n=0;n<scaled_phases.size();++n)
        out<<"    {\"offset_cycles\": "<<scaled_phases[n].first<<", \"cycles\": "<<scaled_phases[n].second<<"}"
           <<(n+1<scaled_phases.size()?",":"")<<"\n";
      out<<"  ],\n  \"dense_renderer_frame_checks_passed\": true,\n  \"scaled_host_renderer_frame_checks_passed\": true,\n  \"physical_testing\": false,\n  \"passed_functional_checks\": true\n}\n";
      require(bool(out),"could not write evidence");
    }
    for(const auto &s:scenes) std::cout<<s.name<<": "<<s.cycles<<" cycles / "<<double(s.cycles)/64000<<" ms at assumed 64 MHz\n";
    std::cout<<"PASS: real SDRAM/arbiter pixel equality, byte lanes, synthetic front/host contention, refresh and reset recovery\n";
    return 0;
  } catch(const std::exception &e) {std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
