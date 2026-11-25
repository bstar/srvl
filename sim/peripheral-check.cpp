// SPDX-License-Identifier: GPL-2.0-or-later
#include "Vsrvl_peripherals.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>

static void check(bool value,const std::string& why) {
    if (!value) throw std::runtime_error(why);
}
class Bench {
public:
    VerilatedContext context;
    Vsrvl_peripherals d{&context};
    void tick() { d.clk=0;d.eval();d.clk=1;d.eval(); }
    void reset() { d.reset=1;tick();tick();d.reset=0; }
    void write(unsigned a,unsigned v) {
        d.address=a;d.write_data=v;d.write_enable=1;tick();d.write_enable=0;
    }
    unsigned read(unsigned a) { d.address=a;d.read_enable=1;d.eval();return d.read_data; }
    void color(unsigned index,unsigned rgb) { write(0x4000+index*2,rgb&255);write(0x4001+index*2,rgb>>8); }
    uint32_t rgb() const { return (uint32_t(d.red)<<16)|(uint32_t(d.green)<<8)|d.blue; }
    std::array<uint32_t,320*204> frame() {
        const auto start=d.frame_count;
        while(d.frame_count==start) tick();
        std::array<uint32_t,320*204> image{};
        unsigned clocks=0,pixels=0,hs=0,vs=0;
        const auto begin=d.frame_count;
        do {
            tick();++clocks;
            check(bool(d.de)==(d.video_x<320 && d.video_y<204),"DE/pipeline coordinate mismatch");
            check(bool(d.hsync)==!(d.video_x>=344 && d.video_x<376),"Horizontal sync mismatch");
            check(bool(d.vsync)==!(d.video_y>=220 && d.video_y<224),"Vertical sync mismatch");
            if (!d.hsync) ++hs;
            if (!d.vsync) ++vs;
            if (d.de) { image[d.video_y*320+d.video_x]=rgb();++pixels; }
            else check(rgb()==0,"Blanking must be black");
        } while(d.frame_count==begin);
        check(clocks==104800 && pixels==320*204,"Native raster extent/period mismatch");
        check(hs==32*262 && vs==4*400,"Sync pulse extent mismatch");
        return image;
    }
};

int main() {
    try {
        Bench b;
        b.d.read_enable=1;b.d.write_enable=0;b.d.buttons=0;b.reset();
        check(!b.d.irq && !b.d.cpu_sleep && b.d.audio_left==0 && b.d.audio_right==0,"Reset outputs");
        for (unsigned a=0x2000;a<0x3000;++a) b.write(a,0);
        b.write(0x2000,'A');b.write(0x2800,0x40);
        b.write(0x2001,0);b.write(0x2801,0x05);
        check(b.read(0x2000)=='A' && b.read(0x2800)==0x40,"Tile/attribute banks alias");
        b.color(0,0x123);b.color(1,0x001);b.color(4,0xa5f);b.color(5,0x06a);b.color(15,0xfed);
        b.write(0x401f,0xff);
        check(b.read(0x401f)==15,"RGB444 high nibble must mask reserved bits");
        b.color(15,0xfed);
        b.write(0x4020,1);
        auto image=b.frame();
        for (unsigned x=0;x<8;++x)
            check(image[x]==((x>=2 && x<=4)?0xaa55ffu:0x112233u),"Glyph row/foreground/background mismatch");
        for (unsigned x=8;x<16;++x) check(image[x]==0x0066aa,"Neighboring tile background mismatch");
        for (unsigned x=0;x<8;++x)
            check(image[3*320+x]==((x>=1 && x<=5)?0xaa55ffu:0x112233u),"Glyph row addressing mismatch");

        // Two overlapping sprites prove slot priority and the three opaque inks.
        b.write(0x4100,40);b.write(0x4101,0);b.write(0x4102,32);b.write(0x4103,0);
        b.write(0x4104,4);b.write(0x4105,1);
        b.write(0x4108,40);b.write(0x4109,0);b.write(0x410a,32);b.write(0x410b,2);
        b.write(0x410c,5);b.write(0x410d,1);
        image=b.frame();
        check(image[35*320+45]==0xaa55ff,"Sprite priority/body color mismatch");
        check(image[37*320+46]==0xffeedd,"Sprite highlight mismatch");
        check(image[34*320+44]==0x000011,"Sprite shadow mismatch");
        check(image[39*320+42]==0xffeedd,"Navigation-light fixture mismatch");
        b.write(0x4105,3);image=b.frame();
        check(image[39*320+42]==0xaa55ff && image[39*320+53]==0xffeedd,"Horizontal sprite flip failed");
        b.write(0x4105,5);image=b.frame();
        check(image[37*320+46]==0xaa55ff && image[42*320+46]==0xffeedd,"Vertical sprite flip failed");

        // The upper half of the expanded sprite bank must not alias lower slots.
        b.write(0x4138,80);b.write(0x4139,0);b.write(0x413a,32);b.write(0x413b,0);
        b.write(0x413c,5);b.write(0x413d,1);b.write(0x413f,0xa5);
        check(b.read(0x413f)==0xa5 && b.read(0x411f)==0,"Upper sprite bank aliases a lower slot");
        image=b.frame();
        check(image[35*320+85]==0x0066aa,"Sprite slot seven was not rendered");
        b.write(0x4105,1);b.write(0x4138,40);image=b.frame();
        check(image[35*320+45]==0xaa55ff,"Upper slot violated sprite-zero priority");

        // Audio phase increment 4096 has exactly 2048 clocks per square-wave edge.
        b.write(0x4300,0);b.write(0x4301,16);b.write(0x4302,2);b.write(0x4303,1);
        b.write(0x4308,0);b.write(0x4309,16);b.write(0x430a,3);b.write(0x430b,1);
        unsigned edges=0,since=0;
        int16_t prior=int16_t(b.d.audio_left);
        for (unsigned i=0;i<12000;++i) {
            b.tick();++since;
            const auto left=int16_t(b.d.audio_left),right=int16_t(b.d.audio_right);
            check(left==256 || left==-256,"Left voice amplitude");
            check(right==384 || right==-384,"Right voice amplitude");
            if (left!=prior) {
                if (edges) check(since==2048,"Tone divider interval mismatch");
                since=0;++edges;prior=left;
            }
        }
        check(edges>=5,"Tone edges missing");
        b.write(0x4303,0);b.d.eval();
        check(b.d.audio_left==0 && b.d.audio_right!=0,"Independent voice gate failed");
        b.write(0x430b,0);

        // Actual 1 kHz counters, independent run/reset, pause/resume and coherent
        // multi-byte reads across a low-byte rollover. Never poke internal HDL.
        b.reset();
        check(b.read(0x4040)==0 && b.read(0x4044)==0,"Stopwatch reset controls");
        b.write(0x4040,3);b.d.read_enable=0;
        for (unsigned i=0;i<6287;++i) b.tick();
        check(b.read(0x4041)==0,"Stopwatch advanced before one millisecond");
        b.tick();
        check(b.read(0x4041)==1,"6288 master clocks must equal one millisecond");
        b.write(0x4040,0);b.d.read_enable=0;
        for (unsigned i=0;i<6288*3;++i) b.tick();
        check(b.read(0x4041)==1,"Stopped timer advanced");
        b.write(0x4040,1);b.d.read_enable=0;
        for (unsigned i=0;i<6288;++i) b.tick();
        check(b.read(0x4041)==2,"Timer resume lost its elapsed time");
        b.write(0x4044,3);b.write(0x4040,2);b.d.read_enable=0;
        for (unsigned i=0;i<6288*3;++i) b.tick();
        check(b.read(0x4041)==0 && b.read(0x4045)==3,"Independent level reset/total accumulation failed");
        b.write(0x4044,0);b.write(0x4040,3);b.d.read_enable=0;
        for (unsigned i=0;i<6288*255;++i) b.tick();
        check(b.read(0x4041)==255,"Timer low-byte fixture mismatch");
        b.tick(); // Snapshot the upper bytes while the low byte is still 255.
        b.d.read_enable=0;
        for (unsigned i=0;i<6288*2;++i) b.tick();
        check(b.read(0x4042)==0 && b.read(0x4043)==0,"Timer upper snapshot tore across rollover");
        check(b.read(0x4041)==1,"Timer did not carry from 255 to 257 ms");
        b.tick();
        check(b.read(0x4042)==1,"New low-byte read did not refresh the upper snapshot");
        check(b.read(0x4045)==3,"Stopped total timer changed while level timer ran");

        b.reset();
        check(b.read(0x4020)==0 && b.read(0x403f)==0,"Reset did not disable video/diagnostic");
        check(b.read(0x2000)=='A',"Reset must retain VRAM; software initializes it");
        b.d.buttons=0xa5;
        b.write(0x4023,1);
        check(b.read(0x4030)==0,"Input changed before frame latch");
        b.write(0x4027,1);
        check(b.d.cpu_sleep,"Frame-wait request was not accepted");
        unsigned waited=0;
        while(!b.d.irq && waited++<104800) b.tick();
        check(b.d.irq && !b.d.cpu_sleep,"Vblank must wake the CPU and assert enabled IRQ");
        check(b.read(0x4030)==0xa5,"Input was not latched at vblank");
        b.d.buttons=0x5a;
        b.write(0x4027,1);
        check(!b.d.cpu_sleep,"An already-pending frame must prevent a sleep race");
        b.write(0x4024,1);
        check(!b.d.irq && b.read(0x4024)==0,"IRQ write-one-to-clear failed");
        check(b.read(0x4030)==0xa5,"Input latch changed within the frame");
        b.write(0x4027,1);
        check(b.d.cpu_sleep,"Sleep failed after IRQ acknowledgment");
        waited=0;while(!b.d.irq && waited++<104800) b.tick();
        check(b.read(0x4030)==0x5a && !b.d.cpu_sleep,"Next-frame wake/input latch failed");
        b.write(0x4023,0);
        check(!b.d.irq && b.read(0x4024)==1,"IRQ mask must preserve pending status");
        b.write(0x403f,0x59);check(b.d.diagnostic==0x59 && b.read(0x403f)==0x59,"Diagnostic latch");
        b.write(0x6000,0xff);check(b.read(0x6000)==0,"Unmapped peripheral read");
        b.d.read_enable=0;b.d.eval();check(b.d.read_data==0,"Disabled read drive");
        std::cout<<"PASS: tile/attribute/palette bus, pipelined 320x204 raster, sprite priority/inks/flips, stereo tone/gates, millisecond timing/pause/resume/independence/coherent rollover, vblank IRQ/input, frame-wait race handling and reset\n";
        return 0;
    } catch (const std::exception& e) { std::cerr<<"FAIL: "<<e.what()<<"\n";return 1; }
}
