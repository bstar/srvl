// SPDX-License-Identifier: GPL-2.0-or-later
#include "machine.hpp"
#include <SDL.h>
#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <thread>

namespace fs=std::filesystem;
static void check(bool value,const std::string& message) {
    if (!value) throw std::runtime_error(message);
}
static void sdl_check(bool value,const std::string& message) {
    check(value,message+": "+SDL_GetError());
}

struct Input {
    std::array<bool,SDL_NUM_SCANCODES> keys{};
    uint8_t controller=0, analog=0;
    bool paused=false, quit=false, reset=false, fullscreen=false;
    uint8_t buttons() const {
        uint8_t b=controller|analog;
        if (keys[SDL_SCANCODE_RIGHT]||keys[SDL_SCANCODE_D]) b|=1;
        if (keys[SDL_SCANCODE_LEFT]||keys[SDL_SCANCODE_A]) b|=2;
        if (keys[SDL_SCANCODE_DOWN]||keys[SDL_SCANCODE_S]) b|=4;
        if (keys[SDL_SCANCODE_UP]||keys[SDL_SCANCODE_W]) b|=8;
        if (keys[SDL_SCANCODE_Z]||keys[SDL_SCANCODE_SPACE]) b|=16;
        if (keys[SDL_SCANCODE_X]) b|=32;
        if (keys[SDL_SCANCODE_RETURN]) b|=64;
        if (keys[SDL_SCANCODE_BACKSPACE]) b|=128;
        return b;
    }
    static uint8_t controller_bit(unsigned button) {
        switch(button) {
            case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:return 1;
            case SDL_CONTROLLER_BUTTON_DPAD_LEFT:return 2;
            case SDL_CONTROLLER_BUTTON_DPAD_DOWN:return 4;
            case SDL_CONTROLLER_BUTTON_DPAD_UP:return 8;
            case SDL_CONTROLLER_BUTTON_A:return 16;
            case SDL_CONTROLLER_BUTTON_B:return 32;
            case SDL_CONTROLLER_BUTTON_START:return 64;
            case SDL_CONTROLLER_BUTTON_BACK:return 128;
            default:return 0;
        }
    }
    void event(const SDL_Event& e) {
        if (e.type==SDL_QUIT) quit=true;
        if (e.type==SDL_WINDOWEVENT && e.window.event==SDL_WINDOWEVENT_FOCUS_LOST) {
            keys.fill(false); controller=analog=0;
        }
        if (e.type==SDL_KEYDOWN || e.type==SDL_KEYUP) {
            const auto key=e.key.keysym.scancode;
            if (unsigned(key)<keys.size()) keys[key]=e.type==SDL_KEYDOWN;
            if (e.type==SDL_KEYDOWN && !e.key.repeat) {
                if (key==SDL_SCANCODE_ESCAPE) quit=true;
                if (key==SDL_SCANCODE_P) paused=!paused;
                if (key==SDL_SCANCODE_R) reset=true;
                if (key==SDL_SCANCODE_F11) fullscreen=!fullscreen;
            }
        }
        if (e.type==SDL_CONTROLLERBUTTONDOWN) controller|=controller_bit(e.cbutton.button);
        if (e.type==SDL_CONTROLLERBUTTONUP) controller&=uint8_t(~controller_bit(e.cbutton.button));
        if (e.type==SDL_CONTROLLERAXISMOTION) {
            if (e.caxis.axis==SDL_CONTROLLER_AXIS_LEFTX) {
                analog&=uint8_t(~3);
                if (e.caxis.value>12000) analog|=1;
                if (e.caxis.value< -12000) analog|=2;
            }
            if (e.caxis.axis==SDL_CONTROLLER_AXIS_LEFTY) {
                analog&=uint8_t(~12);
                if (e.caxis.value>12000) analog|=4;
                if (e.caxis.value< -12000) analog|=8;
            }
        }
    }
};

class Application {
public:
    Console console;
    Input input;
    SDL_Window* window=nullptr;
    SDL_Renderer* renderer=nullptr;
    SDL_Texture* texture=nullptr;
    SDL_GameController* controller=nullptr;
    SDL_AudioDeviceID audio=0;
    bool fullscreen_applied=false;
    Application(bool hidden,bool no_audio) {
        sdl_check(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_AUDIO|SDL_INIT_GAMECONTROLLER)==0,"SDL initialization failed");
        SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY,"0");
        window=SDL_CreateWindow("Circuit Courier - SRVL | Arrows steer, Z jam/start, X slow",
            SDL_WINDOWPOS_CENTERED,SDL_WINDOWPOS_CENTERED,960,612,
            SDL_WINDOW_RESIZABLE|(hidden?SDL_WINDOW_HIDDEN:SDL_WINDOW_SHOWN));
        sdl_check(window,"Cannot create window");
        // Software rendering works on ordinary Wayland/X11 desktops without a
        // host OpenGL driver package being injected into the Nix environment.
        renderer=SDL_CreateRenderer(window,-1,SDL_RENDERER_SOFTWARE);
        sdl_check(renderer,"Cannot create renderer");
        sdl_check(SDL_RenderSetLogicalSize(renderer,Console::width,Console::height)==0,"Cannot set logical display size");
        sdl_check(SDL_RenderSetIntegerScale(renderer,SDL_TRUE)==0,"Cannot set integer scaling");
        texture=SDL_CreateTexture(renderer,SDL_PIXELFORMAT_ARGB8888,SDL_TEXTUREACCESS_STREAMING,
            Console::width,Console::height);
        sdl_check(texture,"Cannot create pixel texture");
        for (int i=0;i<SDL_NumJoysticks();++i) if (SDL_IsGameController(i)) {
            controller=SDL_GameControllerOpen(i);
            if (controller) break;
        }
        if (!no_audio) {
            SDL_AudioSpec wanted{};
            wanted.freq=48000; wanted.format=AUDIO_S16SYS; wanted.channels=2; wanted.samples=1024;
            audio=SDL_OpenAudioDevice(nullptr,0,&wanted,nullptr,0);
            if (audio) SDL_PauseAudioDevice(audio,0);
            else std::cerr<<"Audio device unavailable: "<<SDL_GetError()<<"\n";
        }
    }
    ~Application() {
        if (audio) SDL_CloseAudioDevice(audio);
        if (controller) SDL_GameControllerClose(controller);
        if (texture) SDL_DestroyTexture(texture);
        if (renderer) SDL_DestroyRenderer(renderer);
        if (window) SDL_DestroyWindow(window);
        SDL_Quit();
    }
    void poll() {
        SDL_Event e;
        const bool was_paused=input.paused;
        while (SDL_PollEvent(&e)) {
            input.event(e);
            if (e.type==SDL_CONTROLLERDEVICEADDED && !controller)
                controller=SDL_GameControllerOpen(e.cdevice.which);
            if (e.type==SDL_CONTROLLERDEVICEREMOVED && controller &&
                SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(controller))==e.cdevice.which) {
                SDL_GameControllerClose(controller); controller=nullptr;
                input.controller=input.analog=0;
            }
        }
        if (input.paused!=was_paused && audio) {
            SDL_ClearQueuedAudio(audio);
            SDL_PauseAudioDevice(audio,input.paused);
        }
        if (input.reset) {
            console.reset(); input.reset=false;
            if (audio) SDL_ClearQueuedAudio(audio);
        }
        if (input.fullscreen!=fullscreen_applied) {
            sdl_check(SDL_SetWindowFullscreen(window,input.fullscreen?SDL_WINDOW_FULLSCREEN_DESKTOP:0)==0,"Fullscreen failed");
            fullscreen_applied=input.fullscreen;
        }
    }
    void step(bool queue_audio=true) {
        poll();
        if (!input.paused && !input.quit) {
            console.frame(input.buttons());
            if (audio && queue_audio) {
                // Bound queue latency if the host suspends or changes audio devices.
                if (SDL_GetQueuedAudioSize(audio)>48000u*2u*2u/4u) SDL_ClearQueuedAudio(audio);
                sdl_check(SDL_QueueAudio(audio,console.audio.data(),Uint32(console.audio.size()*sizeof(int16_t)))==0,"Audio queue failed");
            }
        }
    }
    void draw(bool present=true) {
        sdl_check(SDL_UpdateTexture(texture,nullptr,console.pixels.data(),Console::width*4)==0,"Texture upload failed");
        SDL_SetRenderDrawColor(renderer,0,0,0,255);
        sdl_check(SDL_RenderClear(renderer)==0,"Render clear failed");
        sdl_check(SDL_RenderCopy(renderer,texture,nullptr,nullptr)==0,"Pixel rendering failed");
        if (present) SDL_RenderPresent(renderer);
    }
};

static void key(SDL_Scancode code,bool down) {
    SDL_Event event{};
    event.type=down?SDL_KEYDOWN:SDL_KEYUP;
    event.key.state=down?SDL_PRESSED:SDL_RELEASED;
    event.key.keysym.scancode=code;
    event.key.keysym.sym=SDL_GetKeyFromScancode(code);
    sdl_check(SDL_PushEvent(&event)==1,"Synthetic keyboard event was rejected");
}
static void write_wav(const fs::path& path,const std::vector<int16_t>& samples) {
    std::ofstream f(path,std::ios::binary);
    check(bool(f),"Cannot write WAV");
    auto u16=[&](uint16_t v) { f.put(char(v)); f.put(char(v>>8)); };
    auto u32=[&](uint32_t v) { u16(uint16_t(v)); u16(uint16_t(v>>16)); };
    f.write("RIFF",4); u32(uint32_t(36+samples.size()*2)); f.write("WAVEfmt ",8);
    u32(16);u16(1);u16(2);u32(48000);u32(48000*4);u16(4);u16(16);
    f.write("data",4);u32(uint32_t(samples.size()*2));
    for (auto sample:samples) u16(uint16_t(sample));
}

// Test-only maze reconstruction from actual CPU tile writes and ordinary input.
struct Maze {
    std::array<uint8_t,32> masks{};
    static constexpr std::array<int,4> delta={1,-1,8,-8};
    static constexpr std::array<uint8_t,4> bits={1,2,4,8};
    static int x(int n) { return 32+(n%8)*32; }
    static int y(int n) { return 56+(n/8)*32; }
    static int node(int px,int py) { return (px-32+16)/32+((py-56+16)/32)*8; }
    explicit Maze(const Console& c) {
        for (int n=0;n<32;++n) {
            const unsigned a=0x2000+(7+n/8*4)*40+4+n%8*4;
            check(c.writes[a]==1,"Maze junction was not drawn as floor");
            if (n%8<7 && c.writes[a+2]==1) masks[n]|=1;
            if (n%8>0 && c.writes[a-2]==1) masks[n]|=2;
            if (n/8<3 && c.writes[a+80]==1) masks[n]|=4;
            if (n/8>0 && c.writes[a-80]==1) masks[n]|=8;
        }
        for (int n=0;n<32;++n) for (unsigned d=0;d<4;++d) if (masks[n]&bits[d]) {
            const int next=n+delta[d];
            check(next>=0 && next<32 && (masks[next]&bits[d^1]),"Maze edge is not reciprocal");
        }
        for (int n=0;n<32;++n) check(distance(0,n)<32,"Maze has unreachable junctions");
    }
    int direction(int root,int goal,const std::array<bool,32>& blocked={}) const {
        std::array<int,32> first;first.fill(-1);first[root]=0;
        std::array<int,32> queue{};queue[0]=root;unsigned head=0,tail=1;
        while (head<tail) {
            const int n=queue[head++];
            if (n==goal) return first[n];
            for (unsigned d=0;d<4;++d) if (masks[n]&bits[d]) {
                const int next=n+delta[d];
                if (first[next]>=0 || blocked[next]) continue;
                first[next]=n==root?bits[d]:first[n];queue[tail++]=next;
            }
        }
        return -1;
    }
    unsigned distance(int root,int goal) const {
        std::array<int,32> distances;distances.fill(-1);distances[root]=0;
        std::array<int,32> queue{};queue[0]=root;unsigned head=0,tail=1;
        while (head<tail) {
            const int n=queue[head++];
            if (n==goal) return unsigned(distances[n]);
            for (unsigned d=0;d<4;++d) if (masks[n]&bits[d]) {
                const int next=n+delta[d];
                if (distances[next]>=0) continue;
                distances[next]=distances[n]+1;queue[tail++]=next;
            }
        }
        return 255;
    }
};

static bool on_rail(const Console& c,int x,int y) {
    x-=32;y-=56;
    if (x<0 || x>224 || y<0 || y>96 || ((x%32)!=0 && (y%32)!=0)) return false;
    const unsigned a=0x2000+(7+y/32*4)*40+4+x/32*4;
    if (x%32) return c.writes[a+2]==1;
    if (y%32) return c.writes[a+80]==1;
    return c.writes[a]==1;
}

struct MazeDriver {
    int last_x=-1,last_y=-1,heading=0,flee=0;
    uint8_t input(const Console& c,const Maze& maze,int override_goal=-1,bool pulses=true) {
        const int px=int(c.player_x()),py=int(c.player_y());
        if (last_x>=0 && px!=last_x) heading=px>last_x?1:2;
        if (last_y>=0 && py!=last_y) heading=py>last_y?4:8;
        last_x=px;last_y=py;
        const int slot=c.score()<3?8:56;
        const int gx=c.writes[0x4100+slot]+((c.writes[0x4101+slot]&1)<<8),gy=c.writes[0x4102+slot];
        const int goal=override_goal>=0?override_goal:Maze::node(gx,gy);
        const bool ready=c.writes[0x2000+3*40+9]=='J' && c.writes[0x2000+3*40+15]=='A';
        std::array<bool,32> blocked{};
        if (!c.jammed()) for (unsigned i=0;i<c.enemies();++i) {
            const int ex=int(c.enemy_x(i)),ey=int(c.enemy_y(i));
            for (int n=0;n<32;++n)
                if (std::max(std::abs(Maze::x(n)-ex),std::abs(Maze::y(n)-ey))<22) blocked[n]=true;
        }
        auto threat=[&](int dir,int horizon) {
            if (c.jammed()) return false;
            const int dx=dir==1?2:dir==2?-2:0,dy=dir==4?2:dir==8?-2:0;
            for (int t=1;t<=horizon;++t) for (unsigned i=0;i<c.enemies();++i)
                if (std::max(std::abs(px+dx*t-int(c.enemy_x(i))),
                             std::abs(py+dy*t-int(c.enemy_y(i))))<10+t) return true;
            return false;
        };
        const int ox=(px-32)%32,oy=(py-56)%32;
        int root=Maze::node(px,py),remaining=0;
        if (ox) {
            root=(px-32)/32+((py-56)/32)*8;
            if (heading==1) { ++root;remaining=32-ox; } else remaining=ox;
        } else if (oy) {
            root=(px-32)/32+((py-56)/32)*8;
            if (heading==4) { root+=8;remaining=32-oy; } else remaining=oy;
        }
        auto opposite=[](int dir) { return dir==1?2:dir==2?1:dir==4?8:dir==8?4:0; };
        if ((ox || oy) && !ready && threat(heading,4) && flee==0) {
            flee=12;heading=opposite(heading);return uint8_t(heading);
        }
        if (flee>0 && (ox || oy)) { --flee;return uint8_t(heading); }
        int direction=maze.direction(root,goal,blocked);
        if (direction<0) direction=maze.direction(root,goal);
        if (direction==0) direction=heading;
        if (ox || oy) {
            if (remaining>4 || direction==opposite(heading)) direction=heading;
        } else if (!ready && threat(direction,10)) {
            // At a junction choose an escape when the shortest route is occupied.
            int best=-10000;
            for (unsigned d=0;d<4;++d) if (maze.masks[root]&Maze::bits[d]) {
                const int next=root+Maze::delta[d];
                int clearance=10000;
                for (unsigned i=0;i<c.enemies();++i)
                    clearance=std::min(clearance,std::abs(Maze::x(next)-int(c.enemy_x(i)))+
                                                std::abs(Maze::y(next)-int(c.enemy_y(i))));
                const int merit=clearance-int(maze.distance(next,goal))*3-
                                (threat(Maze::bits[d],10)?1000:0);
                if (merit>best) { best=merit;direction=Maze::bits[d]; }
            }
        }
        const uint8_t jam=pulses && ready && threat((ox || oy)?heading:direction,10)?16:0;
        if (jam) flee=0;
        return uint8_t(direction)|jam;
    }
};

static void self_test(Application& app,const fs::path& out) {
    fs::create_directories(out);
    auto& c=app.console;
    uint8_t held=0;
    const std::array<SDL_Scancode,8> codes={SDL_SCANCODE_RIGHT,SDL_SCANCODE_LEFT,SDL_SCANCODE_DOWN,
        SDL_SCANCODE_UP,SDL_SCANCODE_Z,SDL_SCANCODE_X,SDL_SCANCODE_RETURN,SDL_SCANCODE_BACKSPACE};
    auto controls=[&](uint8_t bits) {
        for (unsigned i=0;i<8;++i) if ((held^bits)&(1u<<i)) key(codes[i],bits&(1u<<i));
        held=bits;
    };
    std::vector<int16_t> captured_audio;
    auto frames=[&](unsigned n,uint8_t bits=0) {
        controls(bits);
        for (unsigned i=0;i<n;++i) {
            const auto previous_state=c.state();
            const int previous_x=int(c.player_x()),previous_y=int(c.player_y());
            std::array<int,5> previous_enemy_x{},previous_enemy_y{};
            for (unsigned j=0;j<c.enemies();++j) {
                previous_enemy_x[j]=int(c.enemy_x(j));previous_enemy_y[j]=int(c.enemy_y(j));
            }
            app.step(false);
            if (previous_state==1 && c.state()==1) {
                check(on_rail(c,int(c.player_x()),int(c.player_y())),"Courier left a rail or entered a wall");
                check(std::abs(int(c.player_x())-previous_x)+std::abs(int(c.player_y())-previous_y)<=2,
                      "Courier moved diagonally or exceeded rail speed");
                for (unsigned j=0;j<c.enemies();++j) {
                    const int moved=std::abs(int(c.enemy_x(j))-previous_enemy_x[j])+
                                    std::abs(int(c.enemy_y(j))-previous_enemy_y[j]);
                    check(moved<=1,"Guard exceeded one pixel per frame");
                    check(on_rail(c,int(c.enemy_x(j)),int(c.enemy_y(j))),"Guard crossed a wall");
                    check(!c.jammed() || moved==0,"Jammed guard did not freeze");
                }
            }
            check(c.model.diagnostic!=0xee,"CPU-executed RAM/ROM/unmapped bus test failed");
            check(c.audio.size()==1600,"Expected 800 stereo sample pairs per video frame");
            for (auto sample:c.audio)
                check(sample==0 || sample==768 || sample==-768,"ROM voice amplitude is outside its programmed range");
            // Separate voices have independent phases. Sequential CPU register
            // writes need not yield sample-identical channels at zero crossings.
            for (unsigned offset=0;offset<4;++offset)
                check(c.writes[0x4300+offset]==c.writes[0x4308+offset],"ROM did not configure both stereo voices");
            captured_audio.insert(captured_audio.end(),c.audio.begin(),c.audio.end());
        }
    };
    auto ready=[&] {
        for (unsigned i=0;i<60 && !(c.model.diagnostic&0x80);++i) frames(1);
        check(c.model.diagnostic==0x80,"ROM did not boot to title/zero score");
        frames(2);
    };
    auto displayed_clock=[&](unsigned row,unsigned column) {
        const unsigned base=0x2000+row*40+column;
        check(c.writes[base+2]==':' && c.writes[base+5]=='.',"Timer is not MM:SS.mmm");
        auto digit=[&](unsigned n) {
            check(c.writes[base+n]>='0' && c.writes[base+n]<='9',"Invalid timer digit");
            return unsigned(c.writes[base+n]-'0');
        };
        return (digit(0)*10+digit(1))*60000+(digit(3)*10+digit(4))*1000+
               digit(6)*100+digit(7)*10+digit(8);
    };
    auto clock_ms=[&](unsigned column) { return displayed_clock(5,column); };
    auto start=[&](unsigned expected_level=0) {
        frames(1,16);frames(2);
        check(c.state()==1 && c.score()==0 && c.level()==expected_level,"A did not start the expected circuit");
    };
    auto reset=[&] {
        controls(0);key(SDL_SCANCODE_R,true);app.poll();key(SDL_SCANCODE_R,false);
        ready();
    };
    ready();
    check(c.opcode_fetches>1000 && c.bus_writes>4000,"Boot did not exercise the HDL CPU and bus");
    const auto non_background=std::count_if(c.pixels.begin(),c.pixels.end(),[](uint32_t p) { return (p&0xffffff)!=0x001122; });
    check(non_background>2000,"Boot framebuffer lacks the ROM-drawn display");
    c.screenshot((out/"title.ppm").string());
    // Read back the actual SDL-rendered client surface, verifying nearest-neighbor
    // display scaling rather than just trusting the source framebuffer.
    app.draw(false);
    int width=0,height=0;
    sdl_check(SDL_GetRendererOutputSize(app.renderer,&width,&height)==0,"Renderer size unavailable");
    check(width==960 && height==612,"Unexpected self-test render target size");
    std::vector<uint32_t> surface(unsigned(width*height));
    sdl_check(SDL_RenderReadPixels(app.renderer,nullptr,SDL_PIXELFORMAT_ARGB8888,surface.data(),width*4)==0,"Renderer readback failed");
    for (unsigned y=0;y<Console::height;++y) for (unsigned x=0;x<Console::width;++x)
        for (unsigned dy=0;dy<3;++dy) for (unsigned dx=0;dx<3;++dx)
            check((surface[(y*3+dy)*unsigned(width)+x*3+dx]&0xffffff)==(c.pixels[y*Console::width+x]&0xffffff),
                  "SDL output is not an exact 3x pixel replication");
    app.draw();
    key(SDL_SCANCODE_P,true);key(SDL_SCANCODE_P,false);app.poll();
    const auto paused_clock=c.clocks;app.step(false);
    check(c.clocks==paused_clock && app.input.paused,"Pause advanced the simulated hardware");
    key(SDL_SCANCODE_P,true);key(SDL_SCANCODE_P,false);app.poll();
    check(!app.input.paused,"Pause did not release");
    // Exercise the controller event route without requiring physical gamepads.
    SDL_Event pad{};pad.type=SDL_CONTROLLERBUTTONDOWN;pad.cbutton.button=SDL_CONTROLLER_BUTTON_A;
    sdl_check(SDL_PushEvent(&pad)==1,"Controller event injection failed");
    app.step(false);
    pad.type=SDL_CONTROLLERBUTTONUP;
    sdl_check(SDL_PushEvent(&pad)==1,"Controller release injection failed");
    frames(2);
    check(c.state()==1,"Controller A did not reach the ROM");
    reset();start();
    controls(1);app.poll();
    SDL_Event focus{};focus.type=SDL_WINDOWEVENT;focus.window.event=SDL_WINDOWEVENT_FOCUS_LOST;
    sdl_check(SDL_PushEvent(&focus)==1,"Focus event injection failed");app.poll();held=0;
    check(app.input.buttons()==0,"Focus loss left a movement input stuck");
    auto first_exit=[](uint8_t mask) { for (auto b:Maze::bits) if (mask&b) return b;return uint8_t(0); };
    Maze movement_maze(c);
    const int initial_node=Maze::node(int(c.player_x()),int(c.player_y()));
    const auto initial_dir=first_exit(movement_maze.masks[initial_node]);
    int px=int(c.player_x()),py=int(c.player_y());
    frames(4,initial_dir);
    check(std::abs(int(c.player_x())-px)+std::abs(int(c.player_y())-py)==8,
          "Held direction did not move along the rail");
    px=int(c.player_x());py=int(c.player_y());frames(4);
    check(int(c.player_x())==px && int(c.player_y())==py,
          "Courier kept moving after the direction was released");
    frames(2,3);
    check(int(c.player_x())==px && int(c.player_y())==py,
          "Opposing directions did not stop movement");
    frames(1,initial_dir);
    check(std::abs(int(c.player_x())-px)+std::abs(int(c.player_y())-py)==2,
          "Resuming after a mid-corridor stop snapped or failed to move");
    const auto perpendicular=uint8_t(initial_dir<=2?4:1);
    px=int(c.player_x());py=int(c.player_y());
    frames(3,perpendicular);
    check((initial_dir<=2?int(c.player_y())==py:int(c.player_x())==px),"Turn happened between junctions");
    const auto reverse=uint8_t(initial_dir==1?2:initial_dir==2?1:initial_dir==4?8:4);
    px=int(c.player_x());py=int(c.player_y());frames(1,reverse);
    check((initial_dir==1?int(c.player_x())==px-2:initial_dir==2?int(c.player_x())==px+2:
           initial_dir==4?int(c.player_y())==py-2:int(c.player_y())==py+2),"Mid-corridor reversal failed");
    reset();start();
    Maze slow_maze(c);auto n=Maze::node(int(c.player_x()),int(c.player_y()));
    px=int(c.player_x());py=int(c.player_y());
    frames(6,first_exit(slow_maze.masks[n])|32);frames(1,32);
    check(std::abs(int(c.player_x())-px)+std::abs(int(c.player_y())-py)==6,
          "Slow movement continued without a held direction");
    bool wall_checked=false;
    for (unsigned trial=0;trial<8 && !wall_checked;++trial) {
        reset();frames(trial*3);start();Maze maze(c);
        n=Maze::node(int(c.player_x()),int(c.player_y()));
        const auto blocked=first_exit(uint8_t((~maze.masks[n])&15));
        if (!blocked) continue;
        px=int(c.player_x());py=int(c.player_y());frames(6,blocked);
        check(int(c.player_x())==px && int(c.player_y())==py,"Wall did not stop rail movement");
        wall_checked=true;
    }
    check(wall_checked,"Could not exercise a blocked junction");
    auto measured=clock_ms(8);frames(60);
    check(std::abs(int(clock_ms(8)-measured)-1000)<=1,"HUD timer drift over 60 frames");
    key(SDL_SCANCODE_P,true);key(SDL_SCANCODE_P,false);app.poll();
    measured=clock_ms(8);app.step(false);
    check(clock_ms(8)==measured,"Pause changed the race timer");
    key(SDL_SCANCODE_P,true);key(SDL_SCANCODE_P,false);app.poll();
    reset();start();
    frames(1,16);frames(1);
    check(c.jammed(),"Z did not jam the guards");
    frames(2);c.screenshot((out/"jammed.ppm").string());
    frames(20);
    check(c.jammed(),"Jam wore off before its advertised duration");
    // Release the pulse and allow pursuing guards to establish contact.
    for (unsigned i=0;i<600 && c.state()==1;++i) frames(1);
    check(c.state()==3,"Standing still did not produce a collision or deadline loss");
    frames(2);c.screenshot((out/"link-lost.ppm").string());
    const auto failed_total=clock_ms(25),failed_level=clock_ms(8);
    frames(30);
    check(clock_ms(25)==failed_total && clock_ms(8)==failed_level,"Results menu advanced time");
    start();
    check(clock_ms(8)<100 && clock_ms(25)>=failed_total,"Retry lost the time penalty");
    reset();start();captured_audio.clear();
    std::vector<std::array<unsigned,6>> layouts;
    unsigned failures=0,jams=0;
    for (unsigned stage=0;stage<4;++stage) {
        bool cleared=false;
        for (unsigned attempt=0;attempt<6 && !cleared;++attempt) {
            Maze maze(c);MazeDriver driver;
            check(c.enemies()==stage+2,"Guard count did not increase with the circuit");
            unsigned edges=0;for (auto mask:maze.masks) for (auto bit:Maze::bits) if (mask&bit) ++edges;
            check(edges/2==std::array<unsigned,4>{46,43,40,38}[stage],"Wrong maze obstruction density");
            std::array<unsigned,6> layout={c.player_x(),c.player_y(),
                c.writes[0x4108]+((c.writes[0x4109]&1u)<<8),c.writes[0x410a],
                c.writes[0x4138]+((c.writes[0x4139]&1u)<<8),c.writes[0x413a]};
            check(std::find(layouts.begin(),layouts.end(),layout)==layouts.end(),"Attempt repeated its random route");
            layouts.push_back(layout);
            std::array<int,5> points{};points[0]=Maze::node(int(c.player_x()),int(c.player_y()));
            points[4]=Maze::node(int(layout[4]),int(layout[5]));
            for (unsigned g=0;g<c.enemies();++g)
                check(maze.distance(points[0],Maze::node(int(c.enemy_x(g)),int(c.enemy_y(g))))>=3,
                      "Guard spawned too close to the courier");
            const auto limit=displayed_clock(0,26),prior_total=clock_ms(25)-clock_ms(8);
            unsigned known=0;
            bool captured=false;
            for (unsigned i=0;i<4000 && c.state()==1;++i) {
                if (c.score()<3) {
                    points[c.score()+1]=Maze::node(int(c.writes[0x4108]+((c.writes[0x4109]&1u)<<8)),int(c.writes[0x410a]));
                    known|=1u<<c.score();
                }
                const auto input=driver.input(c,maze);
                if (input&16) ++jams;
                frames(1,input);
                if (!captured && c.score()==1) {
                    c.screenshot((out/(stage==0?"gameplay.ppm":"level-"+std::to_string(stage+1)+".ppm")).string());
                    captured=true;
                }
            }
            if (c.state()!=2) {
                ++failures;
                std::cout<<"Maze attempt lost: circuit "<<stage+1<<", packets "<<c.score()<<", "<<clock_ms(8)<<" / "<<limit<<" ms\n"<<std::flush;
                if (attempt<5) { frames(2);start(stage); }
                continue;
            }
            check(c.score()==3 && known==7 && clock_ms(8)<limit,"Maze delivery did not qualify");
            unsigned distance=0;
            for (unsigned i=0;i<5;++i) {
                check(points[i]>=0 && points[i]<32,"Pickup outside the maze");
                for (unsigned j=0;j<i;++j) check(maze.distance(points[i],points[j])>=2,"Maze pickups overlap");
                if (i) distance+=maze.distance(points[i-1],points[i])*32;
            }
            check(limit==distance*(18-stage)+2000,"Deadline ignored the shortest maze route");
            check(std::abs(int(clock_ms(25)-prior_total)-int(clock_ms(8)))<=3,"Campaign time did not accumulate");
            frames(2);
            if (stage==0) c.screenshot((out/"delivered.ppm").string());
            std::cout<<"Qualified maze circuit "<<stage+1<<": "<<clock_ms(8)<<" / "<<limit<<" ms with "<<c.enemies()<<" guards\n"<<std::flush;
            const auto frozen=clock_ms(25);frames(20);
            check(clock_ms(25)==frozen,"Between-level menu advanced score");
            cleared=true;
        }
        check(cleared,"Could not qualify maze circuit "+std::to_string(stage+1)+" within six real attempts");
        if (stage<3) start(stage+1);
    }
    check(jams>0,"Maze controller did not exercise the jam mechanic");
    frames(2);c.screenshot((out/"campaign-complete.ppm").string());
    std::cout<<"Campaign completed with "<<failures<<" failed attempts and "<<jams<<" jam pulses\n"<<std::flush;
    start();
    check(clock_ms(8)<100 && clock_ms(25)<100,"Campaign replay did not reset clocks");
    std::array<unsigned,2> audible{};
    for (unsigned i=0;i<captured_audio.size();++i) if (captured_audio[i]) ++audible[i&1];
    check(audible[0]>1000 && audible[1]>1000,"ROM gameplay produced insufficient audio in a stereo channel");
    write_wav(out/"gameplay.wav",captured_audio);
    check(app.audio!=0,"Self-test requires an SDL audio device (dummy driver is supported)");
    SDL_PauseAudioDevice(app.audio,1);SDL_ClearQueuedAudio(app.audio);
    app.step(true);
    check(SDL_GetQueuedAudioSize(app.audio)==1600*sizeof(int16_t),"SDL did not queue one frame of stereo samples");
    SDL_ClearQueuedAudio(app.audio);SDL_PauseAudioDevice(app.audio,0);
    reset();
    check(c.state()==0 && c.score()==0,"Hardware reset did not reboot the original ROM");
    std::cout<<"PASS: CPU boot/bus checks, SDL pixels/input/focus/pause/reset, movement/slow mode, guard contact/speed limit, connected mazes, rails/walls/buffered turns/reversals, jam freeze, two-to-five guards, randomized qualified routes, frozen menus/retry penalty, cumulative score/progression/replay and stereo audio\n";
}

int main(int argc,char** argv) {
    try {
        bool test=false,no_audio=false;
        unsigned max_frames=0,benchmark=0;
        fs::path output="build/game-check";
        std::string screenshot;
        for (int i=1;i<argc;++i) {
            const std::string arg=argv[i];
            auto next=[&]() -> std::string { check(i+1<argc,"Missing argument after "+arg);return argv[++i]; };
            if (arg=="--self-test") test=true;
            else if (arg=="--no-audio") no_audio=true;
            else if (arg=="--frames") max_frames=std::stoul(next());
            else if (arg=="--benchmark") benchmark=std::stoul(next());
            else if (arg=="--output-dir") output=next();
            else if (arg=="--screenshot") screenshot=next();
            else if (arg=="--help") {
                std::cout<<"SRVL - Circuit Courier\n"
                    <<"Arrows/WASD steer, Z/Space starts or jams guards, X slows, Enter starts.\n"
                    <<"P pauses, R resets, F11 toggles fullscreen, Esc quits. Gamepads are supported.\n"
                    <<"Options: --self-test --output-dir DIR --benchmark FRAMES --frames N --screenshot FILE.ppm --no-audio\n";
                return 0;
            } else throw std::runtime_error("Unknown option: "+arg);
        }
        if (benchmark) {
            Console c;
            for (int i=0;i<4;++i) c.frame();
            c.frame(16);c.frame();
            const auto start=std::chrono::steady_clock::now();
            for (unsigned i=0;i<benchmark;++i) c.frame();
            const auto seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
            std::cout<<benchmark<<" game frames in "<<seconds<<" seconds: "<<benchmark/seconds<<" simulated fps; target 60 Hz\n";
            return 0;
        }
        Application app(test,no_audio);
        if (test) { self_test(app,output);return 0; }
        std::cout<<"Circuit Courier - arrows/WASD steer, Z/Space jam/start, X slow, P pause, R reset, Esc quit.\n"
            <<"Video driver: "<<SDL_GetCurrentVideoDriver()<<"; audio: "<<(app.audio?SDL_GetCurrentAudioDriver():"disabled")<<"\n"<<std::flush;
        auto deadline=std::chrono::steady_clock::now();
        unsigned frames=0;
        while (!app.input.quit && (!max_frames || frames<max_frames)) {
            app.step();app.draw();
            if (!app.input.paused) ++frames;
            deadline+=std::chrono::nanoseconds(16666667);
            auto now=std::chrono::steady_clock::now();
            if (now<deadline) std::this_thread::sleep_until(deadline);
            else if (now-deadline>std::chrono::milliseconds(250)) deadline=now;
        }
        if (!screenshot.empty()) app.console.screenshot(screenshot);
        return 0;
    } catch (const std::exception& e) {
        std::cerr<<"FAIL: "<<e.what()<<"\n";
        return 1;
    }
}
