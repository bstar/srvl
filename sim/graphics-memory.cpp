// The unchanged SDRAM pin model checks physical timing/geometry independently
// of the controller FSM. A separate byte-lane oracle checks all stored words.
#include "Vgraphics_memory_top.h"
#include "verilated.h"
#include "sdram-model.hpp"
#include <fstream>
#include <iostream>
#include <optional>
#include <random>
#include <tuple>

static void require(bool ok,const std::string &why) { if(!ok) throw std::runtime_error(why); }
struct Operation {
  bool write;
  uint32_t address,data;
  unsigned mask;
  uint64_t offered=0,accepted=0,reads=0,writes=0;
  uint32_t expected=0;
};
using Request=std::tuple<bool,uint32_t,uint32_t,unsigned>;
class Machine {
  std::optional<Request> held;
public:
  Vgraphics_memory_top dut;
  SdramModel memory;
  std::vector<uint32_t> golden=memory.memory;
  std::array<std::optional<Operation>,3> offered{},waiting{};
  std::vector<unsigned> grants;
  uint64_t cycles=0,accepted=0,completed=0,cancelled=0,bypasses=0,turnovers=0;
  uint64_t max_response=0,max_from_offer=0;
  unsigned resets=0;
  bool allow_fault=false;
  Machine() {
    dut.clk=0;dut.reset=1;dut.memory_stall=0;dut.force_response=0;dut.dq_in=0;
    dut.client_valid=0;dut.client_write=0;dut.client_mask=0;
    for(unsigned word=0;word<3;++word) { dut.client_address[word]=0;dut.client_data[word]=0; }
    dut.eval();dut.clk=1;dut.eval();reset();
  }
  void queue(unsigned client,bool write,uint32_t address,uint32_t data=0,unsigned mask=15) {
    require(client<3 && !offered[client] && !waiting[client],"client queued a second request");
    require(address<8388608 && address%4==0 && mask<16,"invalid test operation");
    offered[client]=Operation{write,address,data,mask,cycles};
  }
  void tick() {
    dut.client_valid=0;dut.client_write=0;dut.client_mask=0;
    for(unsigned word=0;word<3;++word) { dut.client_address[word]=0;dut.client_data[word]=0; }
    if(!dut.reset) for(unsigned i=0;i<3;++i) if(offered[i]) {
      const auto &q=*offered[i];dut.client_valid|=1u<<i;dut.client_write|=unsigned(q.write)<<i;
      dut.client_data[i]=q.data;dut.client_mask|=q.mask<<(4*i);
      for(unsigned bit=0;bit<23;++bit) if(q.address&(1u<<bit))
        dut.client_address[(i*23+bit)/32]|=1u<<((i*23+bit)%32);
    }
    dut.clk=0;dut.dq_in=memory.dq();dut.eval();
    memory.edge({bool(dut.sdram_cke),bool(dut.sdram_cs_n),bool(dut.sdram_ras_n),bool(dut.sdram_cas_n),bool(dut.sdram_we_n),bool(dut.dq_oe),
                 uint16_t(dut.sdram_a),uint8_t(dut.sdram_ba),uint8_t(dut.sdram_dqm),uint32_t(dut.dq_out)});
    dut.dq_in=memory.dq();dut.eval();
    if(!dut.reset) {
      const auto replies=unsigned(dut.client_response),takes=unsigned(dut.client_ready & dut.client_valid);
      require((replies&(replies-1))==0 && (takes&(takes-1))==0,"multiple owners in one service slot");
      const Request request{dut.controller_write,dut.controller_address,dut.controller_data,dut.controller_mask};
      if(held) require(dut.controller_valid && request==*held,"controller request changed under backpressure");
      held=dut.controller_valid && (!dut.controller_ready || dut.memory_stall) ? std::optional(request):std::nullopt;
      for(unsigned i=0;i<3;++i) if(replies&(1u<<i)) {
        require(waiting[i].has_value(),"unowned/stale client response");const auto q=*waiting[i];
        require(memory.read_count-q.reads==unsigned(!q.write) && memory.write_count-q.writes==unsigned(q.write),
                "ACK preceded physical operation or issued wrong/duplicate operation");
        require(q.write ? memory.memory.at(q.address/4)==q.expected:dut.client_read_data==q.expected,
                "wrong address, byte mask, read data or response owner");
        max_response=std::max(max_response,cycles-q.accepted);max_from_offer=std::max(max_from_offer,cycles-q.offered);
        waiting[i].reset();++completed;
      }
      for(unsigned i=0;i<3;++i) if(takes&(1u<<i)) {
        require(offered[i] && !waiting[i],"accepted unoffered/duplicate work");auto q=*offered[i];
        q.accepted=cycles;q.reads=memory.read_count;q.writes=memory.write_count;
        auto &word=golden.at(q.address/4);
        if(q.write) for(unsigned lane=0;lane<4;++lane) if(q.mask&(1u<<lane)) {
          const uint32_t mask=255u<<(lane*8);word=(word&~mask)|(q.data&mask);
        }
        q.expected=word;waiting[i]=q;offered[i].reset();++accepted;grants.push_back(i);
        if(dut.controller_valid && dut.controller_ready && !dut.memory_stall) ++bypasses;
      }
      if(replies && takes) ++turnovers;
      require(accepted-completed-cancelled<=1,"more than one accepted request outstanding");
    }
    dut.clk=1;dut.eval();++cycles;
    require(allow_fault || !dut.protocol_fault,"unexpected arbiter protocol fault");
  }
  void idle(unsigned count) { while(count--) tick(); }
  void reset(bool wait=true) {
    for(unsigned i=0;i<3;++i) { if(waiting[i]) ++cancelled;waiting[i].reset();offered[i].reset(); }
    held.reset();dut.reset=1;dut.memory_stall=0;dut.force_response=0;
    // A synchronous logic reset does not erase the physical command already
    // on the pins. Sample that edge before beginning a new initialization audit.
    tick();memory.expect_initialization();idle(3);
    golden=memory.memory;dut.reset=0;++resets;
    if(wait) {
      const auto deadline=cycles+14000;
      while(!dut.initialized && cycles<deadline) tick();
      require(dut.initialized,"SDRAM initialization timeout");idle(3);
    }
    require(!dut.protocol_fault && !dut.client_response,"reset leaked protocol or response state");
  }
  void drain() {
    const auto deadline=cycles+20000;
    while((offered[0] || offered[1] || offered[2] || waiting[0] || waiting[1] || waiting[2]) && cycles<deadline) tick();
    require(cycles<deadline,"memory service failed to drain");
    require(memory.memory==golden,"complete SDRAM storage/guard comparison failed");
  }
  void one(unsigned client,bool write,uint32_t address,uint32_t data=0,unsigned mask=15) {
    queue(client,write,address,data,mask);drain();
  }
};

int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);Machine m;
    // Address/data changes after acceptance cannot replace an initialized or
    // pre-initialization slot. Physical timing still enforces the full 200 us.
    m.reset(false);m.queue(2,true,0x7ffffc,0x12345678);m.idle(30);
    require(m.waiting[2] && !m.dut.initialized,"pre-init request was lost or memory initialized too soon");m.drain();
    for(uint32_t address:{0u,4u,0x3fcu,0x400u,0x7fcu,0x1ffffcu,0x200000u,0x3ffffcu,0x400000u,0x5ffffcu,0x600000u,0x7ffffcu})
      for(unsigned mask=0;mask<16;++mask) {
        const unsigned client=(address/4+mask)%3;
        m.one(client,true,address,0x78563412u^(address*0x9e3779b9u)^(mask*0x10204081u),mask);
        m.one((client+1)%3,false,address);
      }
    // Continuous demand by all clients must rotate 0,1,2 without starvation.
    m.reset();const auto first=m.cycles;const auto grant_start=m.grants.size();
    m.max_response=m.max_from_offer=0;
    std::array<unsigned,3> produced{};
    while(produced[0]<2000 || produced[1]<2000 || produced[2]<2000 || m.accepted!=m.completed+m.cancelled) {
      for(unsigned i=0;i<3;++i) if(produced[i]<2000 && !m.offered[i] && !m.waiting[i]) {
        const unsigned n=produced[i]++;
        m.queue(i,n%2==0,((n*997+i*524287)%2097152)*4,0xf1234567u^(n*37+i*0x87654321u),n%16);
      }
      m.tick();require(m.cycles-first<100000,"continuous clients starved");
    }
    m.drain();
    require(m.grants.size()-grant_start==6000,"contention phase lost work");
    for(size_t n=grant_start;n<m.grants.size();++n) require(m.grants[n]==(n-grant_start)%3,"round-robin order/fairness changed");
    require(m.max_from_offer<=64,"unstalled round-robin service exceeded latency budget");
    const auto contention_cycles=m.cycles-first,fair_response=m.max_response,fair_offer=m.max_from_offer;
    require(m.bypasses && m.turnovers,"bypass and retire/accept paths were not exercised");
    // Random arrival gaps and physical-controller backpressure, with all four
    // banks and every byte mask. An accepted slot must stay coherent throughout.
    std::mt19937 random{0x32c0ffee};produced={};
    const auto randomized_first=m.cycles;
    while(produced[0]<1000 || produced[1]<1000 || produced[2]<1000 || m.accepted!=m.completed+m.cancelled) {
      m.dut.memory_stall=random()%7==0;
      for(unsigned i=0;i<3;++i) if(produced[i]<1000 && !m.offered[i] && !m.waiting[i] && random()%3==0) {
        ++produced[i];m.queue(i,random()%2,(random()%2097152)*4,random(),random()%16);
      }
      m.tick();require(m.cycles-randomized_first<100000,"randomized service failed to progress");
    }
    m.dut.memory_stall=0;m.drain();
    const auto refresh_before=m.memory.refresh_count;
    m.dut.memory_stall=1;m.queue(1,true,0x80000,0x13572468);m.idle(900);
    require(m.waiting[1] && m.memory.refresh_count>refresh_before,"stalled accepted work blocked refresh or completed early");
    m.reset();m.one(2,false,0x80000);
    for(bool write:{false,true}) {
      const auto physical=write ? m.memory.write_count:m.memory.read_count;
      const uint32_t address=write ? 0x200400:0x6007fc;
      m.queue(0,write,address,0x89abcdef);const auto deadline=m.cycles+1000;
      while((write ? m.memory.write_count:m.memory.read_count)==physical && m.cycles<deadline) m.tick();
      require(m.cycles<deadline && m.waiting[0],"could not reach physical in-flight reset");
      m.reset();if(write) require(m.memory.memory.at(address/4)==0x89abcdef,"logic reset rolled back committed data");
      m.one(1,false,address);
    }
    for(bool pending:{false,true}) {
      if(pending) { m.dut.memory_stall=1;m.queue(0,false,0);m.tick(); }
      m.allow_fault=true;m.dut.force_response=1;m.tick();
      require(m.dut.protocol_fault && !m.dut.client_response,"unexpected controller response was silently accepted");
      m.reset();m.allow_fault=false;m.one(2,false,0);
    }
    m.drain();require(m.accepted==m.completed+m.cancelled,"request accounting failed");
    if(argc>1) {
      std::ofstream out(argv[1]);
      out<<"{\n  \"scope\": \"enhanced elastic arbiter and auto-precharge SDRAM RTL against unchanged independent pin/byte-lane models; no CPU, video scanout or physical timing qualification\",\n"
         <<"  \"accepted_transactions\": "<<m.accepted<<",\n  \"completed_transactions\": "<<m.completed<<",\n  \"reset_cancelled_transactions\": "<<m.cancelled
         <<",\n  \"bypass_launches\": "<<m.bypasses<<",\n  \"simultaneous_retire_accepts\": "<<m.turnovers
         <<",\n  \"continuous_requests\": 6000,\n  \"continuous_cycles\": "<<contention_cycles
         <<",\n  \"continuous_max_accepted_to_response_cycles\": "<<fair_response<<",\n  \"continuous_max_offered_to_response_cycles\": "<<fair_offer
         <<",\n  \"refreshes\": "<<m.memory.refresh_count<<",\n  \"max_refresh_gap_cycles\": "<<m.memory.max_refresh_gap
         <<",\n  \"resets\": "<<m.resets<<",\n  \"physical_testing\": false,\n  \"passed\": true\n}\n";
      require(bool(out),"could not record graphics memory evidence");
    }
    std::cout<<"PASS: "<<m.completed<<" memory responses; masks/banks/bounds, strict fairness, elastic bypass/turnover, refresh, backpressure, reset and unexpected-response recovery\n";
    return 0;
  } catch(const std::exception &e) {std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
