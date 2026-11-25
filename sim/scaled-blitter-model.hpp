// Independent software specification for tests only: direct integer division
// per destination sample, not the RTL's incremental remainder/row machinery.
#pragma once
#include <algorithm>
#include <cstdint>
#include <vector>

struct BlitCommand {
  uint16_t tag=0,source_stride=16,destination_stride=640;
  uint32_t source=0x2003,destination=0x180000;
  unsigned source_width=16,source_height=16,width=16,height=16;
  int x=0,y=0;
  unsigned clip_x0=0,clip_y0=0,clip_x1=320,clip_y1=204;
  bool fill=false,fill_covered=true,bpp4=false,flip_x=false,flip_y=false,transparent=true;
  uint8_t fill_index=0,palette=0,band=0;
};
struct BlitExpected { unsigned error=0; uint32_t samples=0,pixels=0; };
inline uint8_t blit_byte(const std::vector<uint32_t> &memory,uint32_t address) {
  return uint8_t(memory.at(address/4)>>(8*(address%4)));
}
inline void blit_byte(std::vector<uint32_t> &memory,uint32_t address,uint8_t byte) {
  auto &word=memory.at(address/4);const unsigned shift=8*(address%4);
  word=(word&~(255u<<shift))|(uint32_t(byte)<<shift);
}
inline BlitExpected blit_reference(std::vector<uint32_t> &memory,const BlitCommand &c) {
  BlitExpected expected;
  if(c.width==0 || c.height==0 || c.width>1024 || c.height>1024 ||
     (!c.fill && (c.source_width==0 || c.source_height==0 || c.source_width>256 || c.source_height>256))) {
    expected.error=1;return expected;
  }
  const uint64_t row=c.bpp4 ? (c.source_width+1)/2:c.source_width;
  if(c.destination%2 || c.destination_stride%2 || c.destination_stride<640 || (!c.fill && c.source_stride<row)) {
    expected.error=2;return expected;
  }
  const uint64_t destination_end=uint64_t(c.destination)+203ull*c.destination_stride+640;
  const uint64_t source_end=c.fill ? 0:uint64_t(c.source)+(c.source_height-1ull)*c.source_stride+row;
  if(destination_end>8388608 || (!c.fill && source_end>8388608)) { expected.error=3;return expected; }
  if(!c.fill && c.source<destination_end && c.destination<source_end) { expected.error=4;return expected; }
  const int x0=std::max({0,c.x,int(c.clip_x0)}),x1=std::min({320,c.x+int(c.width),int(c.clip_x1)});
  const int y0=std::max({0,c.y,int(c.clip_y0)}),y1=std::min({204,c.y+int(c.height),int(c.clip_y1)});
  for(int y=y0;y<y1;++y) for(int x=x0;x<x1;++x) {
    ++expected.samples;
    unsigned index=c.fill_index;
    if(!c.fill) {
      unsigned sx=unsigned(x-c.x)*c.source_width/c.width;
      unsigned sy=unsigned(y-c.y)*c.source_height/c.height;
      if(c.flip_x) sx=c.source_width-1-sx;
      if(c.flip_y) sy=c.source_height-1-sy;
      index=blit_byte(memory,c.source+sy*c.source_stride+(c.bpp4 ? sx/2:sx));
      if(c.bpp4) index=(index>>(4*(sx%2)))&15;
      if(c.transparent && index==0) continue;
      if(c.bpp4) index|=unsigned(c.palette)<<4;
    }
    const uint32_t address=c.destination+unsigned(y)*c.destination_stride+unsigned(x)*2;
    const unsigned word=c.fill && !c.fill_covered ? 0:0x1000|(unsigned(c.band)<<8)|index;
    blit_byte(memory,address,uint8_t(word));blit_byte(memory,address+1,uint8_t(word>>8));
    ++expected.pixels;
  }
  return expected;
}
template<typename Dut> inline void drive_blit(Dut &dut,const BlitCommand &c) {
  dut.command_tag=c.tag;dut.command_fill=c.fill;dut.command_fill_covered=c.fill_covered;dut.command_bpp4=c.bpp4;
  dut.command_flip_x=c.flip_x;dut.command_flip_y=c.flip_y;dut.command_transparent=c.transparent;
  dut.command_fill_index=c.fill_index;dut.command_palette=c.palette;dut.command_band=c.band;
  dut.command_source=c.source;dut.command_destination=c.destination;
  dut.command_source_width=c.source_width;dut.command_source_height=c.source_height;
  dut.command_source_stride=c.source_stride;dut.command_destination_stride=c.destination_stride;
  dut.command_x=uint16_t(c.x)&4095;dut.command_y=uint16_t(c.y)&4095;
  dut.command_width=c.width;dut.command_height=c.height;
  dut.command_clip_x0=c.clip_x0;dut.command_clip_y0=c.clip_y0;
  dut.command_clip_x1=c.clip_x1;dut.command_clip_y1=c.clip_y1;
}
