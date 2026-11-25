// Independent wire/command/model tests for the Tang board services. No games,
// BIOS images, FPGA programming or behavioral replacements for the DUT.
#include "Vtang_services_top.h"
#include "verilated.h"
#include "sdram-model.hpp"
#include <array>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <optional>
#include <random>
#include <string>

static void check(bool ok,const std::string &why) {
  if(!ok) throw std::runtime_error(why);
}
static uint16_t crc16(const std::string &bytes) {
  uint16_t crc=0xffff;
  for(uint8_t byte:bytes) {
    crc^=uint16_t(byte)<<8;
    for(unsigned i=0;i<8;++i) crc=(crc&0x8000) ? uint16_t((crc<<1)^0x1021):uint16_t(crc<<1);
  }
  return crc;
}

class Harness {
  struct Pending { bool write; uint32_t word,expected; uint64_t reads,writes; };
  std::optional<Pending> pending;
  unsigned tx_phase=0,tx_count=0,tx_bit=0;
  uint8_t tx_byte=0;
  bool last_tx=true;
  unsigned rom_guard=0;
  uint16_t guarded_data=0;
public:
  static constexpr unsigned divisor=139;
  Vtang_services_top dut;
  SdramModel memory;
  std::vector<uint32_t> golden;
  std::mt19937 random{0x1ac00217};
  std::string wire_bytes;
  std::vector<std::pair<std::string,std::string>> fixtures;
  std::vector<uint8_t> received;
  uint64_t ticks=0, accepted=0, completed=0, cancelled=0, rom_words=0, bios_writes=0;
  uint64_t framing_errors=0, packets=0, checked_replies=0;
  bool random_grant=false;
  Harness():golden(memory.memory) {
    dut.clk=0; dut.reset=1; dut.rx=1; dut.dq_in=0;
    dut.tx_test=0; dut.tx_test_valid=0; dut.direct_command=1; dut.direct_valid=0;
    dut.memory_test=0; dut.memory_grant=1; dut.test_request=0;
    dut.test_write=0; dut.test_address=0; dut.test_data=0; dut.test_mask=0;
    dut.cart_test_request=0; dut.cart_test_address=0;
    // Establish synchronous reset before the first modeled SDRAM clock edge.
    dut.eval(); dut.clk=1; dut.eval();
  }
  void tick() {
    dut.clk=0; dut.dq_in=memory.dq();
    if(random_grant) dut.memory_grant=(random()%5)==0;
    dut.eval();
    memory.edge({bool(dut.sdram_cke),bool(dut.sdram_cs_n),bool(dut.sdram_ras_n),
                 bool(dut.sdram_cas_n),bool(dut.sdram_we_n),bool(dut.dq_oe),
                 uint16_t(dut.sdram_a),uint8_t(dut.sdram_ba),uint8_t(dut.sdram_dqm),uint32_t(dut.dq_out)});
    dut.dq_in=memory.dq(); dut.eval();
    if(!dut.reset) {
      const bool take=dut.request_ready && (dut.memory_test ? dut.test_request:
                                           dut.bus_request && dut.memory_grant);
      if(take) {
        check(!pending,"controller accepted two outstanding requests");
        const bool write=dut.memory_test ? dut.test_write:dut.bus_write;
        const uint32_t address=dut.memory_test ? dut.test_address:dut.bus_address;
        const uint32_t data=dut.memory_test ? dut.test_data:dut.bus_data;
        const uint8_t mask=dut.memory_test ? dut.test_mask:dut.bus_mask;
        const uint32_t word=address>>2;
        if(write) for(unsigned lane=0;lane<4;++lane) if(mask&(1u<<lane)) {
          const uint32_t field=0xffu<<(8*lane);
          golden[word]=(golden[word]&~field)|(data&field);
        }
        pending=Pending{write,word,golden[word],memory.read_count,memory.write_count}; ++accepted;
      }
    }
    dut.clk=1; dut.eval(); ++ticks;
    if(dut.reset) { pending.reset(); rom_guard=0; }
    else {
      check(!dut.bridge_fault,"loader/cart bridge violated its single-request protocol");
      if(dut.response) {
        check(pending.has_value(),"response without an accepted request");
        const Pending p=*pending;
        if(p.write) {
          check(memory.write_count==p.writes+1 && memory.read_count==p.reads,"write emitted an incorrect number/type of SDRAM operations");
          check(memory.memory[p.word]==p.expected,"write address/lane/data mismatch at byte "+std::to_string(p.word*4));
        } else {
          check(memory.read_count==p.reads+1 && memory.write_count==p.writes,"read emitted an incorrect number/type of SDRAM operations");
          check(dut.read_data==p.expected,"read data or CAS sample phase mismatch at byte "+std::to_string(p.word*4));
        }
        pending.reset(); ++completed;
      }
      if(rom_guard) { check(dut.rom_data==guarded_data,"header data changed before both BS93 bytes were consumed"); --rom_guard; }
      if(dut.rom_write) {
        check(!dut.running,"header/RAM upload while CPU is running");
        guarded_data=dut.rom_data; rom_guard=3; ++rom_words;
      }
      if(dut.bios_write) { check(!dut.running,"BIOS upload while CPU is running"); ++bios_writes; }
      if(dut.packet_command) ++packets;
      if(dut.uart_received_valid) received.push_back(dut.uart_received);
      if(dut.uart_error) ++framing_errors;
    }
    // Independent host-side 8N1 decoder, sampling the FPGA TX wire at bit centers.
    if(dut.reset) { tx_phase=0; last_tx=true; }
    else if(tx_phase==0) {
      if(last_tx && !dut.tx) { tx_phase=1; tx_count=divisor+divisor/2; tx_bit=0; tx_byte=0; }
    } else if(tx_count) --tx_count;
    else if(tx_phase==1) {
      tx_byte|=uint8_t(dut.tx)<<tx_bit;
      tx_count=divisor-1;
      if(++tx_bit==8) tx_phase=2;
    } else {
      check(dut.tx,"FPGA TX invalid stop bit"); wire_bytes.push_back(char(tx_byte)); tx_phase=0;
    }
    last_tx=dut.tx;
  }
  void idle(unsigned cycles) { while(cycles--) tick(); }
  void reset() {
    random_grant=false; dut.memory_grant=1; dut.test_request=0;
    dut.direct_valid=0; dut.tx_test_valid=0; dut.rx=1;
    if(pending) ++cancelled;
    dut.reset=1; tick(); memory.expect_initialization(); idle(7);
    dut.reset=0;
    for(unsigned n=0;!dut.initialized && n<13000;++n) tick();
    check(dut.initialized,"memory failed to initialize");
    idle(8); golden=memory.memory;
    check(!dut.running && !dut.image_valid && !dut.bios_valid,"reset released a game or retained committed status");
    wire_bytes.clear(); received.clear();
  }
  bool command(char op,uint32_t address=0,uint16_t data=0,bool error=false) {
    dut.direct_command=1; dut.direct_opcode=op; dut.direct_address=address;
    dut.direct_data=data; dut.direct_valid=1; tick(); dut.direct_valid=0;
    for(unsigned n=0;!dut.command_done && n<1000;++n) tick();
    check(dut.command_done,"loader command timed out");
    check(bool(dut.command_error)==error,"unexpected command outcome: "+std::string(1,op)+" address="+std::to_string(address));
    return !dut.command_error;
  }
  void byte(uint8_t data,unsigned period=divisor,bool good_stop=true) {
    dut.rx=0; idle(period);
    for(unsigned bit=0;bit<8;++bit) { dut.rx=(data>>bit)&1; idle(period); }
    dut.rx=good_stop; idle(period); dut.rx=1;
  }
  std::string packet_text(char op,uint32_t address=0,uint16_t data=0) {
    char prefix[16],suffix[8];
    std::snprintf(prefix,sizeof(prefix),"%c%06X%04X",op,address,data);
    std::snprintf(suffix,sizeof(suffix),"%04X\n",crc16(prefix));
    return std::string(prefix)+suffix;
  }
  uint32_t packet(const std::string &text,bool error=false,unsigned period=divisor) {
    dut.direct_command=0;
    const size_t start=wire_bytes.size();
    for(uint8_t value:text) byte(value,period);
    for(unsigned n=0;n<60000 && wire_bytes.find('\n',start)==std::string::npos;++n) tick();
    check(wire_bytes.find('\n',start)!=std::string::npos,"packet response timed out");
    const std::string reply=wire_bytes.substr(start,wire_bytes.find('\n',start)-start+1);
    check(reply.size()==14,"response length is not 14 ASCII characters");
    check(reply[0]==(error?'E':'K'),"packet rejected/accepted incorrectly: "+text+" -> "+reply);
    check(crc16(reply.substr(0,9))==std::stoul(reply.substr(9,4),nullptr,16),"response CRC does not match independent host calculation");
    fixtures.emplace_back(text,reply);
    ++checked_replies;
    idle(divisor); // Complete the stop bit before another request.
    return std::stoul(reply.substr(1,8),nullptr,16);
  }
  uint32_t packet(char op,uint32_t address=0,uint16_t data=0,bool error=false) {
    return packet(packet_text(op,address,data),error);
  }
  void memory_op(uint32_t address,bool write,uint32_t data=0,uint8_t mask=15) {
    dut.memory_test=1; dut.test_address=address; dut.test_write=write;
    dut.test_data=data; dut.test_mask=mask; dut.test_request=1;
    const uint64_t before=accepted;
    for(unsigned n=0;accepted==before && n<100;++n) tick();
    check(accepted==before+1,"memory request not accepted"); dut.test_request=0;
    for(unsigned n=0;pending && n<100;++n) tick();
    check(!pending,"memory operation failed to complete");
    tick(); // Keep the test mux selected until the registered response drains.
    dut.memory_test=0;
  }
  void cart_read(uint32_t address) {
    dut.cart_test_address=address; dut.cart_test_request=1; tick(); dut.cart_test_request=0;
    for(unsigned n=0;!dut.cart_test_ack && n<1000;++n) tick();
    check(dut.cart_test_ack,"latched cartridge request was lost under backpressure");
    const uint8_t expected=(golden[address>>2]>>((address&3)*8))&255;
    check(dut.cart_test_byte==expected,"cartridge cache address/byte selection mismatch");
    tick();
  }
  void image(const std::vector<uint8_t> &bytes,bool serial=false) {
    check(!(bytes.size()&1),"test image must have an even byte count");
    for(size_t n=0;n<bytes.size();n+=2) {
      const uint16_t word=bytes[n]|(uint16_t(bytes[n+1])<<8);
      if(serial) packet('W',n,word); else command('W',n,word);
    }
  }
};

int main(int argc,char **argv) {
  try {
    Verilated::commandArgs(argc,argv);
    check(crc16("123456789")==0x29b1,"host CRC reference check vector failed");
    Harness h; h.reset();
    // All byte values on both UART wires, plus legal baud mismatch and noise.
    h.dut.tx_test=1;
    for(unsigned n=0;n<256;++n) {
      const size_t received=h.received.size(), transmitted=h.wire_bytes.size();
      h.byte(n,137+(n%5)); h.idle(2*Harness::divisor);
      check(h.received.size()==received+1 && h.received.back()==n,"UART RX byte/baud mismatch");
      h.dut.tx_test_data=n; h.dut.tx_test_valid=1; h.tick(); h.dut.tx_test_valid=0;
      h.idle(11*Harness::divisor);
      check(h.wire_bytes.size()==transmitted+1 && uint8_t(h.wire_bytes.back())==n,"UART TX byte mismatch");
    }
    const size_t received=h.received.size();
    h.dut.rx=0; h.idle(10); h.dut.rx=1; h.idle(2*Harness::divisor);
    check(h.received.size()==received,"short false start produced a byte");
    const uint64_t errors=h.framing_errors;
    h.byte(0xa5,Harness::divisor,false); h.idle(3*Harness::divisor);
    check(h.framing_errors==errors+1 && h.received.size()==received,"invalid stop bit was accepted");
    h.dut.tx_test=0;
    std::cout<<"PASS: UART all 256 RX/TX values, 137..141 clock bit periods, false-start and framing rejection\n";

    h.reset();
    // Every DQM mask, all banks, row/column endpoints and all word address bits.
    for(unsigned bank=0;bank<4;++bank) for(unsigned mask=0;mask<16;++mask)
      for(uint32_t offset: {0u,4u,0x3fcu,0x400u,0x1ffffcu}) {
        const uint32_t address=(bank<<21)|offset;
        h.memory_op(address,true,h.random(),mask); h.memory_op(address,false);
      }
    for(unsigned bit=2;bit<23;++bit) {
      h.memory_op(1u<<bit,true,h.random()); h.memory_op(1u<<bit,false);
      h.memory_op(0,false);
    }
    for(unsigned n=0;n<30000;++n) {
      const uint32_t address=h.random()&0x7fffff;
      h.memory_op(address,true,h.random(),h.random()&15);
      h.memory_op(address,false);
    }
    const auto refreshes=h.memory.refresh_count;
    h.idle(10000);
    check(h.memory.refresh_count>refreshes,"refresh stopped when idle");
    std::cout<<"PASS: x32 SDRAM geometry, 16 byte masks, four banks, all address bits, 30000 seeded mixed cases and refresh\n";

    h.reset();
    h.command('W',0,0,true);
    h.command('C',9,0,true);
    h.command('K',0,1,true);
    h.command('L');
    h.command('W',1,0,true); h.command('W',2,0,true);
    h.command('W',0x100000,0,true);
    const std::vector<uint8_t> bs93={0x80,0x08,0x02,0x00,0x00,0x0c,'B','S','9','3',
                                   0x18,0x03,0xea,0xea,0xea,0xea,0xea,0xea,0xea,0xea,0xea,0xea};
    h.command('W',0,0x0880);
    const auto writes=h.memory.write_count, words=h.rom_words;
    h.command('W',0,0x0880);
    check(h.memory.write_count==writes && h.rom_words==words,"ACK retry wrote a word twice");
    h.command('W',0,0x0881,true);
    h.command('C',bs93.size()-1,0,true);
    h.command('W',2,0x0002);
    h.random_grant=true;
    for(unsigned n=4;n<bs93.size();n+=2)
      h.command('W',n,bs93[n]|(uint16_t(bs93[n+1])<<8));
    h.random_grant=false; h.dut.memory_grant=1;
    h.command('C',bs93.size()-1);
    check(h.dut.running && h.dut.image_valid && !h.dut.loading,"BS93 did not launch without a BIOS");
    check(h.dut.romsize==bs93.size()-1,"core size must be the last byte address");
    h.command('C',bs93.size()-1); // Lost-ACK retry remains a single launch.
    const auto cache_reads=h.memory.read_count;
    h.cart_read(0); h.cart_read(1); h.cart_read(2); h.cart_read(3);
    check(h.memory.read_count==cache_reads+1,"four adjacent cartridge bytes did not share one cached word");
    h.random_grant=true;
    for(unsigned n=0;n<1000;++n) h.cart_read(h.random()&0xfffff);
    h.random_grant=false; h.dut.memory_grant=1;
    const auto protected_writes=h.memory.write_count,protected_bios=h.bios_writes;
    h.command('W',0,0xffff,true); h.command('B',0,0,true);
    h.command('K',0,0x1ff); check(h.dut.buttons==0x1ff,"buttons did not hold");
    h.command('K',1,0,true); h.command('K',0,0x200,true);
    check(h.dut.buttons==0x1ff,"invalid input changed buttons");
    h.command('K'); check(h.dut.buttons==0,"buttons did not release");
    check(h.memory.write_count==protected_writes && h.bios_writes==protected_bios,"running-game protection failed");
    h.command('R'); check(!h.dut.running && !h.dut.loading,"stop/reset did not hold the game");
    h.command('L');
    auto changed_bs93=bs93; changed_bs93[10]=0x42;
    h.image(changed_bs93); h.command('C',changed_bs93.size()-1); h.cart_read(10);
    check(h.dut.cart_test_byte==0x42,"new image reused stale cached cartridge data");

    // Raw cartridges must have a full BIOS; an incomplete BIOS cannot launch.
    h.command('L');
    std::vector<uint8_t> raw(65536);
    for(unsigned n=0;n<raw.size();++n) raw[n]=(n*17+0x31)^(n>>8);
    h.image(raw); h.command('C',raw.size()-1,0,true);
    h.command('B',1,1,true);
    for(unsigned n=0;n<511;++n) h.command('B',n,(n^0xa5)&255);
    h.command('C',raw.size()-1,0,true);
    h.command('B',511,(511^0xa5)&255);
    const auto bios_count=h.bios_writes;
    h.command('B',511,(511^0xa5)&255);
    check(h.dut.bios_valid && h.bios_writes==bios_count,"BIOS completion or ACK retry incorrect");
    h.command('C',raw.size()-1);
    // A malformed BIOS replacement must invalidate the previous complete BIOS.
    h.command('L'); h.command('B',0,0x5a); check(!h.dut.bios_valid,"partial BIOS replacement retained valid status");
    h.command('B',0,0x100,true); h.command('B',2,0,true);

    // Reset in a backpressured upload discards the candidate and pending launch.
    h.dut.memory_grant=0;
    h.dut.direct_command=1; h.dut.direct_opcode='W'; h.dut.direct_address=0;
    h.dut.direct_data=0x1234; h.dut.direct_valid=1; h.tick(); h.dut.direct_valid=0;
    h.idle(20);
    check(h.dut.loader_request && !h.dut.running,"backpressured upload did not hold reset");
    h.reset();
    h.command('C',9,0,true);
    h.command('L');
    h.dut.direct_opcode='W'; h.dut.direct_address=0; h.dut.direct_data=0xabcd;
    h.dut.direct_valid=1; h.tick(); h.dut.direct_valid=0;
    const auto before_accept=h.accepted;
    while(h.accepted==before_accept) h.tick();
    h.reset(); // An accepted request may be cancelled only by reset.
    h.command('C',9,0,true);

    // LNX is stored with its 64-byte header because the core adds that offset.
    h.command('L');
    for(unsigned n=0;n<512;++n) h.command('B',n,n&255);
    std::vector<uint8_t> lnx(64+65536,0);
    lnx[0]='L'; lnx[1]='Y'; lnx[2]='N'; lnx[3]='X'; lnx[5]=1; lnx[8]=1;
    std::copy(raw.begin(),raw.end(),lnx.begin()+64);
    h.image(lnx); h.command('C',lnx.size()-1);
    check(h.memory.memory[0]==0x584e594c && h.memory.memory[16]==h.golden[16],"LNX header/payload layout incorrect");
    // A second bank is unsupported by the pinned core, so reject it.
    h.command('L'); lnx[6]=1; h.image(lnx); h.command('C',lnx.size()-1,0,true);

    // Test every supported raw size and the final SDRAM word without serial cost.
    for(unsigned size:{131072u,262144u,524288u}) {
      h.command('L'); raw.resize(size);
      for(unsigned n=0;n<size;++n) raw[n]=(n*29+0x47)^(n>>9);
      h.image(raw); h.command('C',size-1);
      check(h.dut.romsize==size-1,"raw cartridge size boundary incorrect");
    }
    std::cout<<"PASS: sequential/idempotent uploads, BIOS completion, BS93/LNX/raw sizes, memory backpressure, commit and running-game protection\n";

    h.reset(); h.dut.direct_command=0;
    check((h.packet('Q')>>16)==0x4c59,"query signature incorrect");
    // Malformed and incomplete frames cannot issue a loader command.
    const auto packets=h.packets;
    std::string bad=h.packet_text('L'); bad[11]=bad[11]=='0'?'1':'0';
    h.packet(bad,true);
    h.packet("W000000GGGG0000\n",true);
    h.packet("L0000\n",true);
    h.packet(h.packet_text('L').substr(0,15)+"0\n",true);
    check(h.packets==packets && !h.dut.loading,"bad packet changed loader state");
    // A bad stop bit taints the current line; the next complete frame recovers.
    h.byte('L',Harness::divisor,false); h.idle(2*Harness::divisor);
    h.packet("\n",true);
    h.packet('L');
    h.image(bs93,true);
    h.packet('C',bs93.size()-1);
    h.packet('K',0,0x10); check(h.dut.buttons==0x10,"serial held input not delivered");
    h.packet('K'); check(h.dut.buttons==0,"serial input release not delivered");
    const auto safe_writes=h.memory.write_count;
    bad=h.packet_text('W',0,0xffff); bad[8]='x'; h.packet(bad,true);
    h.packet('W',0,0xffff,true);
    check(h.dut.running && h.memory.write_count==safe_writes,"corrupt/rejected upload mutated a committed game");
    // Exercise legal case/CRLF framing and end-of-line resynchronization.
    std::string lower="Q0000000000";
    char checksum[8]; std::snprintf(checksum,sizeof(checksum),"%04x\r\n",crc16(lower));
    h.packet(lower+checksum);
    h.packet('R');
    check(h.cancelled==1 && h.accepted==h.completed+h.cancelled,"unexpected lost/duplicate memory request across reset");
    check(h.memory.refresh_count>=4096,"test did not span a full refresh-row budget");
    std::cout<<"PASS: real-wire ASCII/CRC requests and replies, corruption/truncation/framing rejection, serial boot and held/released controls\n";
    std::cout<<"PASS: "<<h.accepted<<" memory requests, "<<h.memory.refresh_count
             <<" refreshes, maximum refresh gap "<<h.memory.max_refresh_gap<<" SDRAM clocks\n";
    if(argc==2) {
      std::ofstream output(argv[1]);
      output<<"{\n  \"scope\": \"UART/packet/loader/controller simulation; no Lynx execution, board timing or physical testing\",\n"
            <<"  \"seed\": \"0x1ac00217\",\n  \"clock_hz\": 64000000,\n  \"baud\": 460800,\n"
            <<"  \"cycles\": "<<h.ticks<<",\n  \"memory_requests\": "<<h.accepted
            <<",\n  \"memory_completions\": "<<h.completed<<",\n  \"refreshes\": "<<h.memory.refresh_count
            <<",\n  \"maximum_refresh_gap_clocks\": "<<h.memory.max_refresh_gap
            <<",\n  \"rom_word_pulses\": "<<h.rom_words<<",\n  \"bios_write_pulses\": "<<h.bios_writes
            <<",\n  \"checked_serial_replies\": "<<h.checked_replies<<",\n  \"passed\": true\n}\n";
      std::ofstream fixture_output("wire-fixtures.tsv");
      auto hex=[](const std::string &bytes) {
        const char *digits="0123456789abcdef"; std::string encoded;
        for(uint8_t byte:bytes) { encoded+=digits[byte>>4]; encoded+=digits[byte&15]; }
        return encoded;
      };
      for(const auto &fixture:h.fixtures)
        fixture_output<<hex(fixture.first)<<"\t"<<hex(fixture.second)<<"\n";
    }
    h.dut.final(); return 0;
  } catch(const std::exception &error) {
    std::cerr<<"FAIL: "<<error.what()<<"\n"; return 1;
  }
}
