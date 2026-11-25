// Stress the queue against an independent software sequence, including RAM
// wrap, producer/consumer stalls, full capacity and reset with pending data.
#include "Vcb_sync_fifo.h"
#include "verilated.h"
#include <deque>
#include <iostream>
#include <random>
#include <stdexcept>

static void require(bool condition,const char *message) {
  if(!condition) throw std::runtime_error(message);
}
int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);
    Vcb_sync_fifo q;
    std::deque<uint32_t> expected;
    std::mt19937 random(0x160102);
    uint64_t accepted=0, consumed=0, cancelled=0, resets=0;
    uint32_t sequence=1;
    bool stalled=false;
    uint32_t held=0;
    auto tick=[&](bool reset,bool valid,bool ready) {
      q.reset=reset; q.input_valid=valid; q.input_data=sequence; q.output_ready=ready;
      q.clk=0; q.eval();
      const bool push=!reset && q.input_valid && q.input_ready;
      if(reset) { cancelled+=expected.size(); expected.clear(); stalled=false; ++resets; }
      else {
        if(stalled) require(q.output_valid && q.output_data==held,"output changed while consumer was stalled");
        if(q.output_valid) {
          require(!expected.empty() && q.output_data==expected.front(),"queue returned missing/out-of-order data");
          if(ready) { expected.pop_front(); ++consumed; }
        }
        stalled=q.output_valid && !ready; held=q.output_data;
        if(push) { expected.push_back(sequence++); ++accepted; }
      }
      q.clk=1; q.eval();
      require(q.level==expected.size(),"queue level differs from independently tracked transactions");
      require(q.level<=257,"queue exceeded physical capacity");
      if(reset) require(!q.output_valid && q.level==0,"reset leaked old output validity");
    };
    tick(true,false,false);
    for(unsigned n=0;n<1000;++n) tick(false,true,false);
    require(expected.size()==257 && !q.input_ready,"full queue did not exert backpressure");
    for(unsigned n=0;n<100;++n) tick(false,true,false);
    for(unsigned n=0;n<1000;++n) tick(false,false,true);
    require(expected.empty() && !q.output_valid,"directed queue drain failed");
    for(unsigned n=0;n<100000;++n)
      tick(n%1997==1996,random()%4!=0,random()%3!=0);
    for(unsigned n=0;n<1000;++n) tick(false,false,true);
    require(expected.empty() && !q.output_valid,"randomized queue drain failed");
    require(accepted==consumed+cancelled,"lost/duplicated queue transaction across reset");
    q.final();
    std::cout<<"PASS: block-RAM queue, "<<accepted<<" accepted, "<<consumed<<" consumed, "
             <<cancelled<<" reset-cancelled, "<<resets<<" resets; stalled output, full/empty and pointer wrap checked\n";
    return 0;
  } catch(const std::exception &error) { std::cerr<<"FAIL: "<<error.what()<<"\n"; return 1; }
}
