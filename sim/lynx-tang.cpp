// Boot the pinned console through the real UART, loader, cart bridge and SDRAM
// controller, using original diagnostic code and an independent SDRAM model.
#include "Vlynx_tang_system.h"
#include "verilated.h"
#include "sdram-model.hpp"
#include <array>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#ifdef VIDEO_CHECK
#include <deque>
#endif
#ifdef AUDIO_CHECK
#include "lynx-audio-monitor.hpp"
#endif

static void require(bool ok,const std::string &why) { if(!ok) throw std::runtime_error(why); }
static uint16_t crc16(const std::string &text) {
  uint16_t crc=0xffff;
  for(uint8_t byte:text) {
    crc^=uint16_t(byte)<<8;
    for(unsigned bit=0;bit<8;++bit) crc=(crc&0x8000) ? uint16_t((crc<<1)^0x1021):uint16_t(crc<<1);
  }
  return crc;
}
class Console {
  unsigned uart_phase=0,uart_count=0,uart_bit=0;
  uint8_t uart_byte=0;
  bool last_tx=true,cart_pending=false;
  uint32_t requested_address=0;
#ifdef VIDEO_CHECK
#ifdef AUDIO_CHECK
  static constexpr unsigned sys_half=504,video_half=1280;
  uint64_t now=0,next_video_edge=292,next_audio_edge=137;
  LynxAudioMonitor audio_monitor;
#else
  static constexpr unsigned sys_half=126,video_half=320;
  uint64_t now=0,next_video_edge=73;
#endif
  std::array<uint16_t,16320> source_pixels{},canvas_pixels{};
  std::array<uint16_t,640*480> transport_pixels{};
  std::deque<std::array<uint16_t,16320>> source_history;
  unsigned source_count=0,canvas_count=0,last_x=0,last_y=0;
  bool have_video=false,canvas_started=false,canvas_active=false;
  uint16_t previous_pixel=0;
  static uint16_t expected_pixel(unsigned address,uint16_t color) {
    const unsigned byte=(address/2)&255;
    const unsigned index=(address&1)?(byte&15):(byte>>4);
    return index==1 ? color:uint16_t(index*0x111);
  }
  void video_pixel() {
    if(core.video_reset) { have_video=false; canvas_started=false; return; }
    const unsigned x=core.video_x,y=core.video_y;
    if(have_video) require(x==(last_x==799?0:last_x+1) && y==(last_x==799?(last_y==524?0:last_y+1):last_y),"video timing lost a pixel");
    have_video=true; last_x=x; last_y=y;
    require(bool(core.video_de)==(x<640 && y<480),"video DE mismatch");
    require(bool(core.video_hsync)==!(x>=656 && x<752),"video horizontal sync mismatch");
    require(bool(core.video_vsync)==!(y>=490 && y<492),"video vertical sync mismatch");
    if(x<640 && y<480) transport_pixels[y*640+x]=core.video_rgb;
    const bool inside=x>=160 && x<480 && y>=138 && y<342;
    if(!inside) { require(core.video_rgb==0,"video border/blanking is not black"); return; }
    const unsigned sx=(x-160)/2,sy=(y-138)/2,address=sy*160+sx;
    if(x==160 && y==138) { canvas_started=true; canvas_active=core.video_frame_valid; canvas_count=0; }
    if(!canvas_started) return;
    if(canvas_active) {
      if((x&1)==0 && ((y-138)&1)==0) canvas_pixels[address]=core.video_rgb;
      else require(core.video_rgb==canvas_pixels[address],"legacy sample was not replicated into an exact 2x2 block");
      if(x&1) require(core.video_rgb==previous_pixel,"horizontal 2x neighbor mismatch");
      previous_pixel=core.video_rgb; ++canvas_count;
    } else require(core.video_rgb==0,"transport frame became visible midway through canvas");
    if(x==479 && y==341 && canvas_active) {
      require(canvas_count==65280,"wrong scaled canvas sample count");
      bool match=false;
      for(const auto &source:source_history) match|=canvas_pixels==source;
      require(match,"transport frame is not one complete captured console frame");
      ++video_frames;
      bool green=true,red=true;
      for(unsigned n=0;n<16320;++n) {
        green&=canvas_pixels[n]==expected_pixel(n,0x0f0);
        red&=canvas_pixels[n]==expected_pixel(n,0xf00);
      }
      if(green) ++video_green;
      if(red) ++video_red;
      canvas_started=false;
    }
  }
  void video_advance(uint64_t target) {
#ifdef AUDIO_CHECK
    while(std::min(next_video_edge,next_audio_edge)<target) {
      const auto time=std::min(next_video_edge,next_audio_edge);
      const bool video=time==next_video_edge,audio=time==next_audio_edge;
      if(video) core.video_clk=!core.video_clk;
      if(audio) core.audio_clk=!core.audio_clk;
      core.eval();
      if(video && core.video_clk) video_pixel();
      if(audio && core.audio_clk) audio_monitor.audio_edge(core.audio_reset,core.audio_frame_strobe,core.audio_frame_valid,
                                                        core.audio_bclk,core.audio_ws,core.audio_sd,core.audio_underrun);
      if(video) next_video_edge+=video_half;
      if(audio) next_audio_edge+=2625;
    }
#else
    while(next_video_edge<target) {
      core.video_clk=!core.video_clk; core.eval();
      if(core.video_clk) video_pixel();
      next_video_edge+=video_half;
    }
#endif
    now=target;
  }
#endif
public:
  Vlynx_tang_system core;
  SdramModel memory;
  std::vector<uint8_t> image;
  std::string replies;
  uint64_t cycles=0,cart_requests=0,cart_acks=0,pixel_events=0;
#ifdef VIDEO_CHECK
  uint64_t video_frames=0,video_green=0,video_red=0;
#endif
  explicit Console(std::vector<uint8_t> bytes):image(std::move(bytes)) {
    core.clk=0; core.reset=1; core.uart_rx=1; core.dq_in=0;
    core.video_clk=0; core.video_reset=1;
    core.audio_clk=0; core.audio_reset=1;
    core.eval(); core.clk=1; core.eval();
  }
  void tick() {
#ifdef VIDEO_CHECK
    video_advance(now+sys_half);
#endif
    core.clk=0; core.dq_in=memory.dq(); core.eval();
    memory.edge({bool(core.sdram_cke),bool(core.sdram_cs_n),bool(core.sdram_ras_n),
                 bool(core.sdram_cas_n),bool(core.sdram_we_n),bool(core.dq_oe),
                 uint16_t(core.sdram_a),uint8_t(core.sdram_ba),uint8_t(core.sdram_dqm),uint32_t(core.dq_out)});
    core.dq_in=memory.dq(); core.eval();
#ifdef VIDEO_CHECK
    video_advance(now+sys_half);
#endif
#ifdef AUDIO_CHECK
    audio_monitor.before_sys(int16_t(core.audio_left),int16_t(core.audio_right),core.running,core.reset);
#endif
    core.clk=1; core.eval(); ++cycles;
#ifdef AUDIO_CHECK
    audio_monitor.after_sys(core.reset,core.audio_snapshot_valid,int16_t(core.audio_snapshot_left),int16_t(core.audio_snapshot_right));
#endif
    if(!core.reset) {
      require(!(core.status&(1u<<12)),"cart bridge reported overlapping/unowned requests");
      if(core.cart_request) {
        require(!cart_pending,"core issued two cartridge requests without an ACK");
        requested_address=core.cart_address; cart_pending=true; ++cart_requests;
      }
      if(core.cart_ack) {
        require(cart_pending,"cartridge ACK without a core request");
        require(requested_address<image.size() && core.cart_byte==image[requested_address],"cartridge data differs from the uploaded image");
        cart_pending=false; ++cart_acks;
      }
      if(core.pixel_write) {
        ++pixel_events;
#ifdef VIDEO_CHECK
        if(core.pixel_address==0) source_count=0;
        if(core.pixel_address==source_count) {
          source_pixels[source_count++]=core.pixel_data;
          if(source_count==16320) {
            source_history.push_back(source_pixels);
            if(source_history.size()>16) source_history.pop_front();
          }
        } else source_count=16320;
#endif
      }
#ifdef VIDEO_CHECK
      require(!(core.status&0x1e00),"buffered console reported capture/scanout/arbiter fault");
      require(core.video_underruns==0,"buffered console missed a line deadline");
#endif
    }
    if(core.reset) { uart_phase=0; last_tx=true; }
    else if(uart_phase==0) {
      if(last_tx && !core.uart_tx) { uart_phase=1; uart_count=139+139/2; uart_bit=0; uart_byte=0; }
    } else if(uart_count) --uart_count;
    else if(uart_phase==1) {
      uart_byte|=uint8_t(core.uart_tx)<<uart_bit; uart_count=138;
      if(++uart_bit==8) uart_phase=2;
    } else {
      require(core.uart_tx,"UART reply stop bit is invalid"); replies.push_back(char(uart_byte)); uart_phase=0;
    }
    last_tx=core.uart_tx;
  }
  void idle(unsigned count) { while(count--) tick(); }
  void byte(uint8_t value) {
    core.uart_rx=0; idle(139);
    for(unsigned bit=0;bit<8;++bit) { core.uart_rx=(value>>bit)&1; idle(139); }
    core.uart_rx=1; idle(139);
  }
  uint32_t command(char op,uint32_t address=0,uint16_t data=0,bool error=false) {
    char prefix[16],checksum[8]; std::snprintf(prefix,sizeof(prefix),"%c%06X%04X",op,address,data);
    std::snprintf(checksum,sizeof(checksum),"%04X\n",crc16(prefix));
    const size_t start=replies.size();
    for(uint8_t value:std::string(prefix)+checksum) byte(value);
    for(unsigned n=0;replies.find('\n',start)==std::string::npos && n<60000;++n) tick();
    require(replies.find('\n',start)!=std::string::npos,"integrated UART command timed out");
    const auto reply=replies.substr(start,replies.find('\n',start)-start+1);
    require(reply.size()==14 && reply[0]==(error?'E':'K'),"integrated UART command rejected/accepted unexpectedly: "+std::string(1,op)+" -> "+reply);
    require(crc16(reply.substr(0,9))==std::stoul(reply.substr(9,4),nullptr,16),"integrated reply CRC mismatch");
    idle(139); return std::stoul(reply.substr(1,8),nullptr,16);
  }
  void upload() {
    command('L');
    require(!core.running,"begin-load did not hold CPU reset");
    for(unsigned n=0;n<image.size();n+=2) {
      command('W',n,image[n]|(uint16_t(image[n+1])<<8));
      require(!core.running,"CPU ran before final image commit");
    }
    command('C',image.size()-1);
    require(core.running,"committed original diagnostic did not start");
  }
  uint64_t frame(uint16_t color,const char *phase) {
    unsigned matched=0;
    for(uint64_t n=0;n<8000000;++n) {
      tick();
      if(core.pixel_write) {
#ifdef VIDEO_CHECK
        const auto expected=expected_pixel(core.pixel_address,color);
#else
        const auto expected=color;
#endif
        if(core.pixel_address==matched && core.pixel_data==expected) ++matched;
        else matched=core.pixel_address==0 && core.pixel_data==expected ? 1:0;
        if(matched==16320) {
#ifdef VIDEO_CHECK
          std::cout<<"PASS: "<<phase<<", one complete ordered patterned 160x102 frame, live palette index 1 = 0x"<<std::hex<<color<<std::dec<<" after "<<n+1<<" master clocks\n";
#else
          std::cout<<"PASS: "<<phase<<", one complete ordered 160x102 RGB444 frame 0x"<<std::hex<<color<<std::dec<<" after "<<n+1<<" master clocks\n";
#endif
          return n+1;
        }
      }
    }
    throw std::runtime_error(std::string("missing complete diagnostic frame: ")+phase+", matched="+std::to_string(matched));
  }
#ifdef VIDEO_CHECK
  void displayed(bool red) {
    const auto before=red?video_red:video_green;
    for(unsigned n=0;n<4500000 && (red?video_red:video_green)==before;++n) tick();
    require((red?video_red:video_green)>before,"expected patterned console frame was never displayed");
#ifdef AUDIO_CHECK
    audio_monitor.phase(red);
#endif
    std::ofstream preview(red?"video-red.ppm":"video-green.ppm",std::ios::binary);
    preview<<"P6\n640 480\n255\n";
    for(uint16_t rgb:transport_pixels)
      for(unsigned shift:{8u,4u,0u}) preview.put(char(((rgb>>shift)&15)*17));
    std::cout<<"PASS: complete patterned console frame, exact 2x scaling and black borders, "<<(red?"A held":"A released")<<"\n";
  }
#endif
#ifdef AUDIO_CHECK
  void check_audio_silence() const { audio_monitor.silent(); }
  void export_audio(std::ostream &out) const {
    require(audio_monitor.phases_checked==6,"not all cold/warm audio/input phases were checked");
    audio_monitor.wave("lynx-stereo.wav");
    out<<"  \"audio_decoded_frames\": "<<audio_monitor.decoded_frames<<",\n"
       <<"  \"audio_source_snapshots\": "<<audio_monitor.source_snapshots<<",\n"
       <<"  \"audio_nonzero_frames\": "<<audio_monitor.nonzero_frames<<",\n"
       <<"  \"audio_input_phases\": "<<audio_monitor.phases_checked<<",\n"
       <<"  \"audio_reference_hz\": 12288000,\n"
       <<"  \"audio_sample_rate_hz\": 48000,\n  \"audio_transport_tested\": true,\n";
    std::cout<<"PASS: "<<audio_monitor.decoded_frames<<" pin-decoded stereo frames from actual Mikey audio; six cold/warm input phases, mute, signed filtering and coherent clock crossing\n";
  }
#endif
};
int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);
    require(argc==3,"expected diagnostic binary and evidence output path");
    std::ifstream stream(argv[1],std::ios::binary);
    require(bool(stream),"cannot read original diagnostic binary");
    std::vector<uint8_t> program{std::istreambuf_iterator<char>(stream),{}};
    if(program.size()&1) program.push_back(0xea);
    std::vector<uint8_t> image{0x80,0x08,0x02,0x00,uint8_t(program.size()>>8),uint8_t(program.size()),'B','S','9','3'};
    image.insert(image.end(),program.begin(),program.end());
    Console sim(std::move(image));
#ifdef AUDIO_CHECK
    sim.idle(32);
#else
    sim.idle(8);
#endif
    sim.core.reset=0; sim.core.video_reset=0; sim.core.audio_reset=0; sim.idle(13000);
    const uint32_t status=sim.command('Q');
    require((status>>16)==0x4c59 && (status&1),"memory not ready through serial status");
    require(!sim.core.running && !sim.pixel_events,"diagnostic ran before upload");
    sim.upload();
    const auto green=sim.frame(0x0f0,"serial boot / button released");
    require(sim.cart_acks>=3,"CPU diagnostic did not exercise actual cartridge requests");
    require(sim.memory.cartridge_read_count==1,"repeated same-word cartridge reads did not use the cache");
#ifdef VIDEO_CHECK
    sim.displayed(false);
#endif
    sim.command('K',0,0x10);
    const auto red=sim.frame(0xf00,"serial A held");
#ifdef VIDEO_CHECK
    sim.displayed(true);
#endif
    sim.command('K');
    const auto release=sim.frame(0x0f0,"serial A released");
#ifdef VIDEO_CHECK
    sim.displayed(false);
#endif
    sim.command('R');
    require(!sim.core.running,"serial recovery/reset did not stop the game");
#ifdef AUDIO_CHECK
    sim.idle(10000); sim.check_audio_silence();
#endif
    sim.command('C',sim.image.size()-1,0,true);
    sim.upload();
    const auto reload=sim.frame(0x0f0,"second serial boot after recovery/reset");
    require(sim.memory.cartridge_read_count==2,"newly loaded game retained a stale cartridge cache word");
#ifdef VIDEO_CHECK
    sim.displayed(false);
    // The previous displayed image was also green. Change the warm-booted
    // game's palette so a retained old frame cannot satisfy reload acceptance.
    sim.command('K',0,0x10);
    sim.frame(0xf00,"warm-boot A held");
    sim.displayed(true);
    sim.command('K');
    sim.frame(0x0f0,"warm-boot A released");
    sim.displayed(false);
#endif
#ifdef AUDIO_CHECK
    const auto audio_status=sim.command('Q');
    require((audio_status&(1u<<13)) && !(audio_status&(1u<<14)),"serial audio-ready/underrun status does not match the running transmitter");
#endif
    require(sim.cart_acks==sim.cart_requests && sim.cart_acks>=6,"unanswered/insufficient cartridge requests");
    std::ofstream output(argv[2]);
#ifdef VIDEO_CHECK
    output<<"{\n  \"scope\": \"UART-loaded patterned Lynx diagnostic through actual core, capture, arbiter, SDRAM, dual-clock line buffers and exact 2x RGB transport; no video serializer/board timing\",\n"
          <<"  \"scaled_video_frames\": "<<sim.video_frames<<",\n  \"video_green_frames\": "<<sim.video_green<<",\n  \"video_red_frames\": "<<sim.video_red<<",\n"
          <<"  \"warm_input_frames_verified\": true,\n"
          <<"  \"physical_testing\": false,\n  \"display_transport_tested\": \"parallel RGB/timing in simulation\",\n";
#else
    output<<"{\n  \"scope\": \"UART-loaded pinned Lynx CPU/Suzy/Mikey, local RAM, loader/cart bridge and command-modeled SDRAM; RGB source stream only\",\n"
          <<"  \"physical_testing\": false,\n  \"display_transport_tested\": false,\n";
#endif
#ifdef AUDIO_CHECK
    sim.export_audio(output);
#endif
    output
          <<"  \"cycles\": "<<sim.cycles<<",\n  \"image_bytes\": "<<sim.image.size()
          <<",\n  \"ordered_frame_pixels\": 16320,\n  \"frame_cycles\": ["<<green<<","<<red<<","<<release<<","<<reload
          <<"],\n  \"cartridge_requests\": "<<sim.cart_requests<<",\n  \"cartridge_acks\": "<<sim.cart_acks
          <<",\n  \"external_cartridge_reads\": "<<sim.memory.cartridge_read_count<<",\n  \"refreshes\": "<<sim.memory.refresh_count
          <<",\n  \"passed\": true\n}\n";
    sim.core.final();
    std::cout<<"PASS: integrated serial boot/reload, original CPU/cart/RAM/math/display behavior, input, SDRAM and cache invalidation\n";
    return 0;
  } catch(const std::exception &error) { std::cerr<<"FAIL: "<<error.what()<<"\n"; return 1; }
}
