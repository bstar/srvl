// Decode only observed BCLK/WS/SD pins. Bit placement follows the I2S bus
// contract: WS switches a bit before the MSB, 16 payload + zero slot padding.
#pragma once
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <utility>

class I2sDecoder {
  bool have_pins=false,old_bclk=false,old_ws=false,old_sd=false;
  bool have_slot=false,slot_ws=false,have_left=false,have_edge=false;
  unsigned position=0;
  uint16_t word=0,left_word=0;
  uint64_t ticks=0,last_edge=0;
  static void check(bool ok,const char *why) { if(!ok) throw std::runtime_error(why); }
public:
  using Pair=std::pair<int16_t,int16_t>;
  void reset() { *this=I2sDecoder{}; }
  std::optional<Pair> observe(bool bclk,bool ws,bool sd) {
    ++ticks;
    std::optional<Pair> completed;
    if(have_pins) {
      if(ws!=old_ws || sd!=old_sd) check(old_bclk && !bclk,"I2S data/WS changed away from a falling bit-clock edge");
      if(bclk!=old_bclk) {
        if(have_edge) check(ticks-last_edge==2,"I2S bit clock was not an integer divide-by-four");
        have_edge=true; last_edge=ticks;
      }
      if(!old_bclk && bclk) {
        if(!have_slot) {
          if(!ws) { have_slot=true; slot_ws=false; position=0; word=0; check(!sd,"I2S initial delay bit not zero"); }
        } else if(ws!=slot_ws) {
          check(position==31,"I2S channel slot is not 32 bit clocks");
          if(!slot_ws) { left_word=word; have_left=true; }
          else { check(have_left,"I2S right channel arrived before left"); completed=Pair{int16_t(left_word),int16_t(word)}; }
          slot_ws=ws; position=0; word=0;
          check(!sd,"I2S one-bit channel delay/padding is not zero");
        } else {
          ++position; check(position<=31,"I2S word-select transition missing");
          if(position<=16) word=uint16_t((word<<1)|sd);
          else check(!sd,"I2S trailing padding is not zero");
        }
      }
    }
    have_pins=true; old_bclk=bclk; old_ws=ws; old_sd=sd;
    return completed;
  }
};
