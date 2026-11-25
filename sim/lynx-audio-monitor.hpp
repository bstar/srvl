// Compare serialized sound with independently filtered actual core samples.
#pragma once
#include "audio-model.hpp"
#include "i2s-decoder.hpp"
#include <algorithm>
#include <cmath>
#include <deque>
#include <fstream>
#include <string>
#include <vector>

class LynxAudioMonitor {
  AudioModel reference;
  I2sDecoder decoder;
  AudioModel::Pair expected_snapshot{};
  std::deque<AudioModel::Pair> snapshots,frames;
  std::vector<AudioModel::Pair> pcm;
  static void check(bool ok,const char *message) { if(!ok) throw std::runtime_error(message); }
public:
  uint64_t decoded_frames=0,source_snapshots=0,nonzero_frames=0;
  unsigned phases_checked=0;
  void before_sys(int16_t left,int16_t right,bool running,bool reset) {
    expected_snapshot=reference.output(running);
    reference.step(left,right,running,reset);
  }
  void after_sys(bool reset,bool valid,int16_t left,int16_t right) {
    if(!reset && valid) {
      check(AudioModel::Pair{left,right}==expected_snapshot,"real-core audio snapshot differs from independent signed filter model");
      snapshots.push_back({left,right}); ++source_snapshots;
    }
  }
  void audio_edge(bool reset,bool strobe,bool valid,bool bclk,bool ws,bool sd,bool underrun) {
    if(reset) { decoder.reset(); return; }
    check(!underrun,"real-core audio transport underrun");
    if(strobe) {
      if(valid) {
        check(!snapshots.empty(),"audio frame consumed a stereo snapshot that does not exist");
        frames.push_back(snapshots.front()); snapshots.pop_front();
      } else frames.emplace_back(0,0);
    }
    if(const auto pair=decoder.observe(bclk,ws,sd)) {
      check(!frames.empty() && *pair==frames.front(),"I2S decoded samples differ from actual coherently captured core audio");
      frames.pop_front(); pcm.push_back(*pair); ++decoded_frames;
      if(pair->first || pair->second) ++nonzero_frames;
    }
  }
  void silent() const {
    check(pcm.size()>=4,"insufficient audio for mute check");
    for(size_t n=pcm.size()-4;n<pcm.size();++n) check(pcm[n]==AudioModel::Pair{0,0},"game stop did not produce whole silent stereo frames");
  }
  void phase(bool held) {
    check(pcm.size()>=384,"insufficient audio for active phase check");
    unsigned peak_l=0,peak_r=0,cross_l=0,cross_r=0,different=0;
    bool positive_l=false,negative_l=false,positive_r=false,negative_r=false;
    for(size_t n=pcm.size()-384;n<pcm.size();++n) {
      const auto [l,r]=pcm[n];
      peak_l=std::max(peak_l,unsigned(std::abs(int(l)))); peak_r=std::max(peak_r,unsigned(std::abs(int(r))));
      positive_l|=l>0; negative_l|=l<0; positive_r|=r>0; negative_r|=r<0;
      different+=l!=r;
      if(n>pcm.size()-384) {
        cross_l+=pcm[n-1].first<=0 && l>0;
        cross_r+=pcm[n-1].second<=0 && r>0;
      }
    }
    check(positive_l && negative_l && positive_r && negative_r && different>192,"audio is silent, DC or incorrectly mixed to mono");
    check(cross_l>=14 && cross_l<=18 && cross_r>=18 && cross_r<=22,"observed diagnostic tone frequencies are outside the expected 2/2.5 kHz windows");
    check(peak_l>(held?450u:900u) && peak_l<=(held?512u:1024u),"left diagnostic volume does not follow the A button");
    check(peak_r>(held?225u:450u) && peak_r<=(held?256u:512u),"right diagnostic volume does not follow the A button");
    ++phases_checked;
  }
  void wave(const std::string &path) const {
    std::ofstream out(path,std::ios::binary);
    const auto u16=[&](uint16_t v){out.put(char(v));out.put(char(v>>8));};
    const auto u32=[&](uint32_t v){u16(uint16_t(v));u16(uint16_t(v>>16));};
    out.write("RIFF",4); u32(uint32_t(pcm.size()*4+36)); out.write("WAVEfmt ",8);
    u32(16); u16(1); u16(2); u32(48000); u32(48000*4); u16(4); u16(16);
    out.write("data",4); u32(uint32_t(pcm.size()*4));
    for(const auto [l,r]:pcm) { u16(uint16_t(l));u16(uint16_t(r)); }
  }
};
