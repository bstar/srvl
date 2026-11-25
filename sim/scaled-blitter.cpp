#include "Vcb_scaled_blitter.h"
#include "verilated.h"
#include "scaled-blitter-model.hpp"
#include <array>
#include <fstream>
#include <iostream>
#include <optional>
#include <random>
#include <stdexcept>
#include <tuple>

static void require(bool ok,const std::string &why) { if(!ok) throw std::runtime_error(why); }
using Request=std::tuple<bool,uint32_t,uint32_t,unsigned>;
class Machine {
  struct Pending { Request request; uint64_t due; };
  std::optional<Pending> pending;
  std::optional<Request> held;
  std::mt19937 random{0x51ca1e};
public:
  Vcb_scaled_blitter dut;
  std::vector<uint32_t> memory=std::vector<uint32_t>(2097152);
  uint64_t cycles=0,accepted=0,completed=0,cancelled=0,reads=0,writes=0,written_bytes=0;
  unsigned resets=0;
  bool slow=true,force_response=false;
  Machine() {
    for(uint32_t i=0;i<memory.size();++i) memory[i]=0xb631a947u^(i*0x9e3779b9u);
    dut.clk=0;dut.reset=0;dut.command_valid=0;dut.completion_ready=0;
    dut.memory_ready=0;dut.memory_response=0;dut.memory_read_data=0;
    drive_blit(dut,BlitCommand{});reset();
  }
  Request request() const { return {bool(dut.memory_write),dut.memory_address,dut.memory_data,dut.memory_mask}; }
  void tick() {
    dut.clk=0;
    const bool reply=!dut.reset && pending && pending->due<=cycles;
    dut.memory_ready=!dut.reset && !pending && (!slow || random()%4!=0);
    dut.memory_response=reply || force_response;
    if(reply && !std::get<0>(pending->request)) dut.memory_read_data=memory.at(std::get<1>(pending->request)/4);
    dut.eval();
    if(!dut.reset) {
      if(held) require(dut.memory_valid && request()==*held,"request changed while backpressured");
      if(pending) require(request()==pending->request,"accepted request fields changed before response");
      if(reply) {
        const auto [write,address,data,mask]=pending->request;
        if(write) for(unsigned lane=0;lane<4;++lane) if(mask&(1u<<lane)) {
          blit_byte(memory,address+lane,uint8_t(data>>(8*lane)));++written_bytes;
        }
        ++completed;pending.reset();
      }
      if(dut.memory_valid && dut.memory_ready) {
        require(!pending,"second outstanding memory request");
        require((dut.memory_address&3)==0 && dut.memory_address<8388608,"unaligned/out-of-range memory request");
        if(dut.memory_write) {
          require(dut.memory_mask==3 || dut.memory_mask==12 || dut.memory_mask==15,"write does not cover whole surface pixels");
          ++writes;
        } else { require(!dut.memory_mask,"unexpected read byte mask");++reads; }
        pending=Pending{request(),cycles+(slow ? 1+random()%19:1)};
        ++accepted;
      }
      held=dut.memory_valid && !dut.memory_ready ? std::optional<Request>(request()):std::nullopt;
    }
    dut.clk=1;dut.eval();++cycles;
    require(!(dut.completion_valid && (pending || dut.memory_valid)),"completion fence preceded final memory acknowledgment");
  }
  void reset() {
    if(pending) { ++cancelled;pending.reset(); }
    held.reset();dut.reset=1;tick();tick();dut.reset=0;dut.eval();++resets;
    require(dut.command_ready && !dut.completion_valid && !dut.protocol_fault,"reset failed to clear command/completion/protocol state");
  }
  bool waiting() const { return bool(pending); }
  bool waiting_write() const { return pending && std::get<0>(pending->request); }
  void assets(const BlitCommand &c) {
    if(c.fill || c.source_width<1 || c.source_height<1 || c.source_width>256 || c.source_height>256) return;
    const uint64_t extent=uint64_t(c.source)+(c.source_height-1ull)*c.source_stride+(c.bpp4 ? (c.source_width+1)/2:c.source_width);
    if(extent>8388608) return;
    for(unsigned y=0;y<c.source_height;++y) for(unsigned x=0;x<c.source_width;++x) {
      const unsigned index=((x*7+y*11+unsigned(c.tag))%7==0) ? 0:1+(x*13+y*17)%unsigned(c.bpp4?15:255);
      const auto address=c.source+y*c.source_stride+(c.bpp4?x/2:x);
      if(c.bpp4) {
        const unsigned shift=4*(x%2),old=blit_byte(memory,address);
        blit_byte(memory,address,uint8_t((old&~(15u<<shift))|(index<<shift)));
      } else blit_byte(memory,address,uint8_t(index));
    }
  }
  void start(const BlitCommand &c) {
    require(dut.command_ready,"attempted command while not ready");
    drive_blit(dut,c);dut.command_valid=1;tick();dut.command_valid=0;
    BlitCommand junk;junk.x=-777;junk.width=0;junk.destination=8388607;junk.tag=~c.tag;
    drive_blit(dut,junk); // Accepted descriptors must be independent of input changes.
  }
};

static uint64_t commands=0,samples=0,pixels=0,command_cycles=0,slow_stalls=0;
static std::array<uint64_t,5> error_counts{};
static void check(Machine &m,BlitCommand c) {
  c.tag=uint16_t(++commands);
  m.assets(c);auto expected_memory=m.memory;
  const auto expected=blit_reference(expected_memory,c);
  const auto first=m.cycles,reads=m.reads,writes=m.writes,bytes=m.written_bytes;
  m.start(c);
  const auto deadline=m.cycles+8000000;
  while(!m.dut.completion_valid && m.cycles<deadline) m.tick();
  require(m.dut.completion_valid,"command timed out, case "+std::to_string(commands));
  require(!m.dut.protocol_fault,"unexpected memory protocol fault");
  require(m.dut.completion_tag==c.tag && m.dut.completion_error==expected.error,"completion tag/error wrong, case "+std::to_string(commands));
  require(m.dut.command_cycles==m.cycles-first,"cycle counter includes completion backpressure or misses command work");
  require(m.dut.sampled_pixels==expected.samples && m.dut.written_pixels==expected.pixels,"sample/write count differs from reference");
  require(m.dut.read_requests==m.reads-reads && m.dut.write_requests==m.writes-writes,"memory request counters differ");
  require(m.written_bytes-bytes==uint64_t(expected.pixels)*2,"byte masks wrote more/fewer bytes than accepted pixels");
  require(!c.fill || m.reads==reads,"fill unnecessarily fetched source memory");
  if(c.fill && expected.samples==320*204 && c.destination%4==0 && c.destination_stride%4==0)
    require(m.writes-writes==320*204/2,"full aligned clear/fill did not write two pixels per word");
  if(m.memory!=expected_memory) {
    for(size_t i=0;i<m.memory.size();++i) if(m.memory[i]!=expected_memory[i])
      throw std::runtime_error("pixel/memory mismatch case "+std::to_string(commands)+" at byte "+std::to_string(i*4)+
                               " actual="+std::to_string(m.memory[i])+" expected="+std::to_string(expected_memory[i]));
  }
  samples+=expected.samples;pixels+=expected.pixels;command_cycles+=m.dut.command_cycles;slow_stalls+=m.dut.memory_stalls;
  ++error_counts.at(expected.error);
  const auto snapshot=std::make_tuple(m.dut.completion_tag,m.dut.completion_error,m.dut.command_cycles,m.dut.sampled_pixels,
                                     m.dut.written_pixels,m.dut.read_requests,m.dut.write_requests,m.dut.memory_stalls);
  m.dut.command_valid=1;
  for(unsigned i=0;i<23;++i) {
    m.tick();require(!m.dut.command_ready && m.dut.completion_valid,"completion was not held under backpressure");
    require(snapshot==std::make_tuple(m.dut.completion_tag,m.dut.completion_error,m.dut.command_cycles,m.dut.sampled_pixels,
                                     m.dut.written_pixels,m.dut.read_requests,m.dut.write_requests,m.dut.memory_stalls),"completion fields/counters changed while held");
  }
  m.dut.command_valid=0;m.dut.completion_ready=1;m.tick();m.dut.completion_ready=0;
  require(m.dut.command_ready && !m.dut.completion_valid,"completion acknowledgment did not release command slot");
}

int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);Machine m;BlitCommand c;
    for(bool bpp4:{false,true}) for(bool fx:{false,true}) for(bool fy:{false,true}) {
      for(const auto [w,h]:{std::pair{16u,16u},{37u,23u},{7u,5u},{1u,1u},{320u,204u}}) {
        c=BlitCommand{};c.bpp4=bpp4;c.palette=11;c.band=9;c.flip_x=fx;c.flip_y=fy;
        c.source_width=17;c.source_height=13;c.source_stride=23;c.width=w;c.height=h;
        c.x=-3;c.y=-2;c.clip_x0=1;c.clip_y0=1;check(m,c);
      }
    }
    c=BlitCommand{};c.fill=true;c.transparent=true;c.width=320;c.height=204;check(m,c);
    c.source_width=0;c.source_height=0;c.source_stride=0;c.source=8388607;c.width=7;c.height=3;check(m,c);
    c.fill_index=209;c.band=15;c.x=1;c.width=319;c.destination_stride=642;c.destination+=2;check(m,c);
    c.fill_covered=false;check(m,c);
    // Paired fills must preserve neighboring halfwords, stride holes and the
    // bottom/right guard, even when the row's starting halfword alternates.
    for(unsigned offset:{0u,2u}) for(unsigned stride:{640u,642u})
      for(int x:{0,1,319}) for(unsigned width:{1u,2u,3u,320u}) for(bool covered:{false,true}) {
        c=BlitCommand{};c.fill=true;c.fill_covered=covered;c.fill_index=0xd9;c.band=13;
        c.destination+=offset;c.destination_stride=uint16_t(stride);c.x=x;c.y=202;c.width=width;c.height=3;
        check(m,c);
      }
    // Exercise both sides of the single-carry fast path, including the final
    // source sample and row transitions with each format and flip direction.
    for(bool bpp4:{false,true}) for(bool fx:{false,true}) for(bool fy:{false,true})
      for(unsigned width:{15u,16u,17u}) {
        c=BlitCommand{};c.bpp4=bpp4;c.flip_x=fx;c.flip_y=fy;c.width=width;c.height=width;
        c.x=-1;c.y=-1;c.source_stride=19;check(m,c);
      }
    for(unsigned bad=0;bad<12;++bad) {
      c=BlitCommand{};
      switch(bad) {
        case 0:c.width=0;break; case 1:c.height=1025;break;case 2:c.source_width=257;break;
        case 3:c.source_height=0;break;case 4:c.destination+=1;break;case 5:c.destination_stride=641;break;
        case 6:c.destination_stride=638;break;case 7:c.source_stride=1;break;
        case 8:c.destination=8388606;break;case 9:c.source=8388607;break;
        case 10:c.source=c.destination;break;case 11:c.source_height=256;c.source_stride=65535;break;
      }
      check(m,c);
    }
    for(const auto [x,y]:{std::pair{-2048,-2048},{2047,2047},{-1023,-1000},{319,203}}) {
      c=BlitCommand{};c.x=x;c.y=y;c.width=1024;c.height=1024;c.flip_x=true;c.flip_y=true;check(m,c);
    }
    c=BlitCommand{};c.clip_x0=91;c.clip_x1=23;check(m,c);
    c=BlitCommand{};c.source_width=1;c.source_height=1;c.source_stride=1;c.source=8388607;c.width=99;c.height=71;check(m,c);
    c=BlitCommand{};c.source_width=1;c.source_height=120;c.source_stride=65535;c.source=0;c.destination=7864320;check(m,c);
    c=BlitCommand{};c.destination=8388608-130560;c.x=319;c.y=203;check(m,c);
    for(bool fx:{false,true}) for(bool fy:{false,true}) {
      c=BlitCommand{};c.source_width=256;c.source_height=256;c.source_stride=259;
      c.width=1;c.height=1;c.x=7;c.y=5;c.flip_x=fx;c.flip_y=fy;check(m,c);
    }
    std::mt19937 random{0xcb204320};
    for(unsigned n=0;n<320;++n) {
      c=BlitCommand{};c.source=0x1001+random()%64;c.bpp4=random()%2;c.fill=random()%9==0;
      c.source_width=1+random()%256;c.source_height=1+random()%256;
      c.source_stride=uint16_t((c.bpp4?(c.source_width+1)/2:c.source_width)+random()%13);
      c.width=1+random()%430;c.height=1+random()%240;c.x=int(random()%430)-110;c.y=int(random()%300)-90;
      c.flip_x=random()%2;c.flip_y=random()%2;c.transparent=random()%2;
      c.palette=uint8_t(random()%16);c.band=uint8_t(random()%16);c.fill_index=uint8_t(random());c.fill_covered=random()%2;
      c.clip_x0=random()%30;c.clip_y0=random()%20;c.clip_x1=200+random()%121;c.clip_y1=100+random()%105;
      c.destination+=2*(random()%2);c.destination_stride=640+2*(random()%9);
      m.slow=n%2;check(m,c);
    }
    // Reset with a backpressured read, accepted read/write and buffered pixels.
    for(unsigned phase=0;phase<4;++phase) {
      c=BlitCommand{};c.tag=0xbeef;c.width=80;c.height=60;m.assets(c);m.start(c);
      const auto deadline=m.cycles+100000;
      for(;;) {
        if((phase==0 && m.dut.memory_valid && !m.dut.memory_ready) ||
           (phase==1 && m.waiting() && !m.waiting_write()) ||
           (phase==2 && m.waiting_write()) ||
           (phase==3 && m.dut.written_pixels>0 && m.dut.write_requests==0)) break;
        require(m.cycles<deadline,"could not reach reset stimulus phase");m.tick();
      }
      m.reset();for(unsigned n=0;n<31;++n) { m.tick();require(!m.dut.completion_valid && !m.dut.memory_valid,"reset leaked old command activity"); }
      check(m,BlitCommand{});
    }
    m.force_response=true;m.tick();m.force_response=false;
    require(m.dut.protocol_fault,"unexpected response was not reported");m.reset();check(m,BlitCommand{});
    require(m.accepted==m.completed+m.cancelled,"transaction accounting mismatch");
    require(error_counts[0] && error_counts[1] && error_counts[2] && error_counts[3] && error_counts[4],"missing command-validation coverage");
    if(argc>1) {
      std::ofstream out(argv[1]);
      out<<"{\n  \"scope\": \"scaled sprite/fill RTL against direct integer pixel reference and delayed memory model; no CPU/SDRAM/scanout integration\",\n"
         <<"  \"commands\": "<<commands<<",\n  \"sampled_pixels\": "<<samples<<",\n  \"written_pixels\": "<<pixels
         <<",\n  \"command_cycles\": "<<command_cycles<<",\n  \"memory_stall_cycles\": "<<slow_stalls
         <<",\n  \"accepted_transactions\": "<<m.accepted<<",\n  \"completed_transactions\": "<<m.completed
         <<",\n  \"reset_cancelled_transactions\": "<<m.cancelled<<",\n  \"resets\": "<<m.resets
         <<",\n  \"physical_testing\": false,\n  \"passed\": true\n}\n";
      require(bool(out),"could not write evidence");
    }
    std::cout<<"PASS: "<<commands<<" commands, "<<samples<<" exact samples, "<<pixels<<" surface pixels; 4/8-bpp, flips, clipping, fills, masks, fences, backpressure and reset\n";
    return 0;
  } catch(const std::exception &e) {std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
