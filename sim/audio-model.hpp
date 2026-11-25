// Independent mathematical recurrence for the documented Q16 four-pole filter.
// Use 64-bit arithmetic and explicit floor division, rather than RTL widths.
#pragma once
#include <array>
#include <cstdint>
#include <stdexcept>
#include <utility>

class AudioModel {
  std::array<std::array<int64_t,4>,2> state{};
  static int64_t floor_div(int64_t x,int64_t d) { return x>=0 ? x/d:-((-x+d-1)/d); }
public:
  using Pair=std::pair<int16_t,int16_t>;
  Pair output(bool enable) const {
    if(!enable) return {0,0};
    return {int16_t(floor_div(state[0][3]+32768,65536)),int16_t(floor_div(state[1][3]+32768,65536))};
  }
  void step(int16_t left,int16_t right,bool enable,bool reset) {
    if(reset || !enable) { state={}; return; }
    const std::array<int16_t,2> input{left,right};
    const auto old=state;
    for(unsigned channel=0;channel<2;++channel) {
      for(unsigned pole=0;pole<4;++pole) {
        const int64_t target=pole ? old[channel][pole-1]:int64_t(input[channel])*65536;
        state[channel][pole]=old[channel][pole]+floor_div(target-old[channel][pole],1024);
        if(state[channel][pole]<INT32_MIN || state[channel][pole]>INT32_MAX)
          throw std::runtime_error("audio filter escaped its signed 32-bit state range");
      }
    }
  }
};
