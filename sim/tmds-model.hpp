// Independent byte/word model. Use cumulative XOR and direct emitted-bit
// counting rather than the RTL encoder's closed-form disparity updates.
#pragma once
#include <cstdint>
#include <stdexcept>

class TmdsModel {
public:
  int disparity=0;
  static unsigned ones(unsigned value) { unsigned n=0; while(value) { n+=value&1; value>>=1; } return n; }
  static uint16_t control(unsigned bits) {
    constexpr uint16_t words[]{0x354,0x0ab,0x154,0x2ab}; return words[bits&3];
  }
  uint16_t encode(uint8_t byte,bool active,unsigned controls=0) {
    if(!active) { disparity=0; return control(controls); }
    unsigned prefix=0,parity=0;
    for(unsigned n=0;n<8;++n) { parity^=(byte>>n)&1; prefix|=parity<<n; }
    const unsigned count=ones(byte);
    const bool xnor=count>4 || (count==4 && !(byte&1));
    const unsigned chain=prefix^(xnor?0xaa:0), tag=xnor?0:1;
    const int delta=2*int(ones(chain))-8;
    const bool invert=(disparity==0 || delta==0) ? !tag:((disparity>0)==(delta>0));
    const auto word=uint16_t((unsigned(invert)<<9)|(tag<<8)|(chain^(invert?255:0)));
    disparity+=2*int(ones(word))-10;
    if(disparity<-8 || disparity>8) throw std::runtime_error("TMDS running disparity escaped its defined bound");
    return word;
  }
  static uint8_t decode(uint16_t word) {
    const unsigned chain=(word&255)^((word&512)?255:0);
    const unsigned bits=(chain^(chain<<1))&255;
    return uint8_t(bits^((word&256)?0:0xfe));
  }
};
