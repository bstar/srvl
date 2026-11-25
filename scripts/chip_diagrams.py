"""Original, inspectable SVG engineering diagrams for the chip design handbook.

These are logical architecture proposals, not physical floorplans or new FPGA
measurements. Node definitions drive both exported SVG and the HTML inspector.
"""

import html
import json
from pathlib import Path
import textwrap


COLORS = {"project": "#b9e48c", "reused": "#91cce4", "integration": "#efc17e"}


def e(value):
    return html.escape(str(value), quote=True)


class Diagram:
    def __init__(self, key, title, subtitle, height=720):
        self.key, self.title, self.subtitle, self.height = key, title, subtitle, height
        self.nodes, self.wires, self.zones, self.notes = [], [], [], []

    def node(self, key, x, y, w, title, subtitle, detail, inputs, outputs, gate,
             kind="project", state="Proposed", h=100):
        self.nodes.append(dict(key=key, x=x, y=y, w=w, h=h, title=title,
                               subtitle=subtitle, detail=detail, inputs=inputs,
                               outputs=outputs, gate=gate, kind=kind, state=state))

    def wire(self, points, label="", at=None, kind="project", both=False, dashed=False):
        self.wires.append(dict(points=points, label=label, at=at, kind=kind,
                               both=both, dashed=dashed))

    def zone(self, x, y, w, h, label):
        self.zones.append((x, y, w, h, label))

    def note(self, x, y, text):
        self.notes.append((x, y, text))

    def svg(self):
        prefix = "chip-" + self.key
        parts = [f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1120 {self.height}" role="group" aria-labelledby="{prefix}-title {prefix}-desc" class="chip-svg">
          <title id="{prefix}-title">{e(self.title)}</title><desc id="{prefix}-desc">{e(self.subtitle)}. Logical architecture; inspectable blocks describe scope and acceptance.</desc>
          <defs><pattern id="{prefix}-grid" width="24" height="24" patternUnits="userSpaceOnUse"><circle cx="1" cy="1" r=".7" fill="#59735f" opacity=".32"/></pattern>''']
        for kind, color in COLORS.items():
            parts.append(f'<marker id="{prefix}-arrow-{kind}" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 1 1 L 8 5 L 1 9" fill="none" stroke="{color}" stroke-width="1.5"/></marker>')
        parts.append(f'''</defs><rect width="1120" height="{self.height}" fill="#15271f"/><rect width="1120" height="{self.height}" fill="url(#{prefix}-grid)"/>
          <path d="M24 69H1096" stroke="#405846"/><text x="30" y="34" fill="#e4f0da" font-family="sans-serif" font-size="20" font-weight="600">{e(self.title)}</text>
          <text x="30" y="55" fill="#a9bea0" font-family="monospace" font-size="10">{e(self.subtitle)}</text>
          <text x="1090" y="34" text-anchor="end" fill="#9db98c" font-family="monospace" font-size="10">CB / {e(self.key.upper())}</text>''')
        for x, y, w, h, label in self.zones:
            parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#223a2a" fill-opacity=".35" stroke="#607b53" stroke-dasharray="5 5"/><text x="{x+14}" y="{y+20}" fill="#a6bf95" font-family="monospace" font-size="9" letter-spacing="1">{e(label)}</text>')
        for wire in self.wires:
            points = wire["points"]
            path = "M " + " L ".join(f"{x} {y}" for x, y in points)
            kind, color = wire["kind"], COLORS[wire["kind"]]
            attrs = f' marker-end="url(#{prefix}-arrow-{kind})"'
            if wire["both"]:
                attrs += f' marker-start="url(#{prefix}-arrow-{kind})"'
            if wire["dashed"]:
                attrs += ' stroke-dasharray="5 5"'
            parts.append(f'<path d="{path}" fill="none" stroke="{color}" stroke-width="1.7" stroke-linejoin="round"{attrs}/>')
        # Put labels above wires, so their background masks crossings cleanly.
        for wire in self.wires:
            if wire["label"] and wire["at"]:
                x, y = wire["at"]
                width = len(wire["label"]) * 6.1 + 12
                parts.append(f'<rect x="{x-6}" y="{y-11}" width="{width}" height="17" fill="#15271f"/><text x="{x}" y="{y}" fill="{COLORS[wire["kind"]]}" font-family="monospace" font-size="10">{e(wire["label"])}</text>')
        for n in self.nodes:
            x, y, w, h = (n[k] for k in ["x", "y", "w", "h"])
            color = COLORS[n["kind"]]
            title_lines = textwrap.wrap(n["title"], max(18, int((w-32)/10.2)))
            parts.append(f'''<g data-chip-node="{e(n['key'])}" role="button" tabindex="0" aria-label="{e(n['title'] + ': ' + n['state'])}" aria-pressed="false">
              <title>{e(n['title'])}</title><desc>{e(n['detail'])}</desc>
              <rect class="node-box" x="{x}" y="{y}" width="{w}" height="{h}" fill="#233b2b" stroke="{color}" stroke-opacity=".65"/>
              <path d="M{x} {y+14}V{y+h-14}" stroke="{color}" stroke-width="3"/>
              <text x="{x+15}" y="{y+18}" fill="{color}" font-family="monospace" font-size="8" letter-spacing=".7">{e(n['state'].upper())}</text>''')
            for i, line in enumerate(title_lines[:2]):
                parts.append(f'<text x="{x+15}" y="{y+43+i*19}" fill="#e4eedc" font-family="sans-serif" font-size="17" font-weight="550">{e(line)}</text>')
            subtitle_y = y + h - 15
            parts.append(f'<text x="{x+15}" y="{subtitle_y}" fill="#b0c4a2" font-family="monospace" font-size="9">{e(n["subtitle"])}</text>')
            for dy in [30, 43, 56]:
                parts.append(f'<path d="M{x-5} {y+dy}h5m{w} 0h5" stroke="{color}" opacity=".65"/>')
            parts.append('</g>')
        for x, y, text in self.notes:
            parts.append(f'<text x="{x}" y="{y}" fill="#b4c7aa" font-family="monospace" font-size="10">{e(text)}</text>')
        legend_y = self.height - 24
        parts.append(f'<path d="M24 {legend_y-19}H1096" stroke="#405846"/>')
        for x, kind, label in [(30, "project", "PROJECT LOGIC / PROPOSAL"), (365, "reused", "REUSED IMPLEMENTATION"), (700, "integration", "INTEGRATION / QUALIFICATION")]:
            parts.append(f'<rect x="{x}" y="{legend_y-8}" width="7" height="7" fill="{COLORS[kind]}"/><text x="{x+15}" y="{legend_y}" fill="#b3c5aa" font-family="monospace" font-size="9">{label}</text>')
        parts.append('</svg>')
        return "".join(parts)


def definitions(evidence):
    diagrams = []
    d = Diagram("system", "The enhanced console · logical partition", "Proposed FPGA modules · no enhanced-system fit or timing claim", 860)
    d.zone(25, 94, 1070, 558, "SINGLE FPGA / LOGICAL ENGINE BOUNDARIES")
    d.node("cpu", 55, 140, 225, "65C02 orchestrator", "Game logic and scene setup", "Reuse the native CPU family/core; submit bounded work to specialized engines. The final enhanced clock and stall adapter need validation.", "ROM/RAM, interrupts, controller state", "MMIO requests, commands, scene state", "CPU stall/IRQ tests and integrated timing", "reused", "Reused CPU / new integration")
    d.node("registers", 365, 140, 270, "Registers + command bridge", "Held commands / coherent results", "Experimental nonblocking $4400 MMIO and dual-clock mailboxes pass an actual CPU diagnostic. Staging writes cannot replace submitted work. A general external-memory CPU stall/cache adapter remains open.", "CPU register writes and engine completion", "One command/result, status and IRQ", "Exactly-once MMIO, cold/warm CPU ROM, reset and clock-phase tests",state="CPU diagnostic passes")
    d.node("local", 800, 140, 255, "Local ROM / RAM", "Boot and working state", "Allocate local storage after measuring the complete enhanced configuration. This is not the legacy core's fixed 64 KiB work RAM allocation.", "CPU address, data and control", "Instruction/data results", "Mapped RAM inference and latency-correct CPU access", "integration", "Budget open")
    for args in [
        ("sprites",55,"Scaled sprite engine","Inverse sampling and clipping","Autonomous destination walking, source fetch, transparency and writes.","Sprite commands, source pixels","Object-surface writes","Independent pixel model and stalled writes"),
        ("compositor",415,"Parallax compositor","Tiles, priority and line buffers","Fetch independently scrolling planes and resolve visible candidates.","Layer state, tiles, object candidates","Completed RGB lines","Priority/scroll and scanout-deadline tests"),
        ("geometry",775,"Math + triangle engine","Fixed-point help and flat fill","CPU scene preparation plus hardware arithmetic and screen-space coverage.","Math requests, clipped ordered triangles","Arithmetic results, covered-pixel writes","Integer arithmetic/coverage model and bounded scenes"),
    ]:
        key,x,title,sub,detail,inp,out,gate=args
        d.node(key,x,325,280,title,sub,detail,inp,out,gate,
               state="Blitter component verified" if key=="sprites" else "Proposed")
    d.node("scanout",55,540,240,"Display + line buffers","Fixed transport cadence","Consume only completed buffers; final panel and transport details are separate choices.","Completed RGB lines, buffer ownership","RGB/timing and underrun status","Pixel mapping, CDC and transport timing", "integration", "Integration planned")
    d.node("arbiter",365,540,390,"Memory scheduler + controller","Queues / reserved service / refresh","Coordinate clients using explicit completion and bounded buffering. Useful service and maximum latency must be measured.","CPU, fetch, draw and scanout requests","Memory commands, data and completions","Independent SDRAM model and contended deadlines", "integration", "Integration planned")
    d.node("panel",55,700,240,"Backlit color display","Border-free visible game area","The full logical canvas is 320x204; legacy pixels fill it at exact 2x with no added borders. Final panel adaptation must preserve every source edge. Qualify motion, power and availability before PCB/case freeze.","Qualified transport and backlight power","Complete border-free game image","Actual panel and active-area mapping acceptance", "integration", "Unselected component")
    d.node("sdram",800,700,255,"External SDRAM","Tang: packaged 8 MiB x32","Existing memory silicon stores assets and surfaces. A complete controller/arbiter budget is still needed.","Controller commands and writes","Read data and storage","Functional, timing and physical memory acceptance", "integration", "Board memory / port pending")
    d.wire([(280,190),(365,190)],"MMIO",(295,177))
    d.wire([(170,140),(170,119),(928,119),(928,140)],"CPU-local access",(600,114),kind="reused")
    d.wire([(500,240),(500,280),(195,280),(195,325)])
    d.wire([(500,280),(555,280),(555,325)],"commands / state",(380,269))
    d.wire([(555,280),(915,280),(915,325)])
    for x in [195,555,915]:
        d.wire([(x,425),(x,480),(560,480),(560,540)])
    d.note(660,467,"scheduled fetches / writes")
    d.wire([(365,585),(295,585)],"lines",(302,569))
    d.wire([(175,640),(175,700)],"RGB",(192,675),kind="integration")
    d.wire([(755,585),(928,585),(928,700)],"data / byte lanes",(790,572),kind="integration",both=True)
    d.wire([(55,190),(35,190),(35,515),(560,515),(560,540)],"CPU / loader requests",(95,505),kind="integration",both=True,dashed=True)
    diagrams.append(d)

    d = Diagram("sprites", "Scaled sprites · pixels through the engine", "Implemented v1 + SDRAM/CPU tests · frame ownership, compositor and complete-system timing remain open", 700)
    d.node("command",45,140,270,"Command + bounds", "Latch state once accepted", "Latch one descriptor. Check dimensions, strides, physical 8 MiB bounds and conservative source/surface non-overlap. Invalid commands complete with an error and no memory access.","Descriptor fields, command valid/ready","Coherent descriptor and clipped bounds","Invalid dimensions/strides/ranges, empty clip and reset",state="Validation checks pass")
    d.node("walk",425,140,270,"Destination walker","Half-open clipped rectangle","Intersect the rectangle with the 320x204 surface and user clip. Initial source phase includes the clipped-away destination offset.","Signed origin, dimensions and user clip","Destination XY and preserved source phase","Negative origins, screen edges and stride padding",state="Pixel reference passes")
    d.node("sample",805,140,270,"Exact remainder sampler","Floor mapping / independent flips","Advance an integer remainder and subtract the destination size while carrying into the source position. Unity/enlargement carry in the sampling/store cycle; minification retains repeated carries. This exactly matches floor(relative*source/destination) without a DSP or divider.","Source/destination sizes and saved row phase","Source XY and byte/nibble selection","Direct division reference at enlargement/minification extremes",state="Exact sampling passes")
    d.node("fetch",45,370,270,"32-bit source cache","Packed 4-bit or 8-bit indices","One aligned word holds eight 4-bit or four 8-bit samples. Rows may have byte padding and an unaligned base. The source must stay immutable until completion.","Source address/format and memory responses","Decoded source index and read counters","Word boundaries, odd packed widths and delayed responses",state="Memory model + SDRAM pass")
    d.node("ink",425,370,270,"Coverage + index + band","Zero transparency / palette bank","Test raw zero before banking. A 16-bit word stores coverage, four band bits and eight index bits, preserving opaque color zero separately from an empty pixel. RGB lookup remains future work.","Source index, palette bank, band and fill coverage","Covered object pixel, clear or suppressed write","Banked zero, opaque zero, clears and untouched transparent bytes",state="Pixel reference passes")
    d.node("writes",805,370,270,"One-word write combiner","Paired fills / fused sample stores","Cached samples enter the combiner directly; a sample behind a flush resumes on its ACK. Fill emits one or two pixels per word with edge masks. Hold requests through backpressure and ACK. There is one outstanding transaction and no destination read.","Destination pixel/address and write ACK","Masked memory writes and counters","Both halfwords, stride holes, stalls and delayed final ACK",state="Memory model + SDRAM pass")
    d.node("source",45,550,270,"Shared SDRAM service","Real arbiter + controller in test","The integration test competes with scheduled front-surface reads and host traffic. It measures scene cycles but does not include a native scanout or CPU.","Draw, synthetic front and host requests","Physical SDRAM commands and responses","Pixel equality, refresh and explicit 60 Hz budget results", "integration", "Integration model passes",h=90)
    d.node("fence",805,550,270,"Held completion token","Tag + error + counters","The final token waits for the last write ACK and stays stable until accepted. Frame ownership, vblank publication and CPU IRQ/MMIO adapters remain outside this component.","Command end and memory completions","Held completion valid, tag and status","No early fence; held completion and joint-reset cancellation",state="Fence/reset checks pass",h=90)
    d.wire([(315,190),(425,190)],"descriptor",(330,177))
    d.wire([(695,190),(805,190)],"XY / phase",(707,177))
    d.wire([(940,240),(940,310),(180,310),(180,370)],"source coordinates",(460,301))
    d.wire([(315,420),(425,420)],"samples",(335,406))
    d.wire([(695,420),(805,420)],"pixels",(720,406))
    d.wire([(180,550),(180,470)],"reads",(195,515),kind="integration",both=True)
    d.wire([(940,470),(940,550)],"commit ACK",(955,515))
    d.note(425,586,"src_x = floor(relative_x * src_w / dst_w)")
    d.note(425,607,"clipping must preserve the sample phase")
    diagrams.append(d)

    d = Diagram("compositor", "Parallax · independent planes to one visible line", "Three illustrated planes are examples, not a maximum or measured layer budget", 760)
    for key,x,y,title,scroll in [("far",45,135,"Distant plane","small scroll offset"),("middle",70,265,"Middle plane","independent X / Y"),("near",95,395,"Near plane","larger visible motion")]:
        d.node(key,x,y,280,title,scroll,"Each proposed tile plane has independent map/scroll and palette state. Depth comes from different offsets; this diagram does not set a layer count.","Plane map, scroll, palette and raster state","Line-specific fetch state","Independent offsets, wrapping and state-latch tests")
    d.node("tiles",480,220,245,"Map + pattern fetch","Fetch ahead of the beam","Resolve tile row data with bounded caches/queues. The first map and pattern formats remain to be specified.","Latched plane state, memory responses","Plane pixel candidates","Tile-edge, format and randomized-latency tests")
    d.node("priority",820,220,255,"Priority resolver","Transparent samples fall through","Select visible candidates deterministically, including equal-priority ties and object insertion bands.","Plane and object candidates","Winning color/index and palette state","Unique-color overlap and transparent-tie cases")
    d.node("objects",820,390,255,"Object candidates","Completed surface or buffer","Choose a representation that avoids unnecessary destination reads. Surface/band encoding is not finalized.","Completed object data and ownership","Object pixel with priority/band","Ownership and combined sprite/layer stress")
    d.node("palette",480,575,245,"Palette expansion","Native color-latch contract","Expand selected native indices under a defined palette timing rule; legacy RGB capture is separate.","Winning index and palette selection","RGB sample","Raster palette changes and exact output colors")
    d.node("line",820,575,255,"Completed line buffer","Scanout never waits for tiles","Switch buffers only after coherent fill completion. Underflow needs an explicit status and output policy.","RGB samples and fill-complete token","Stable line for display transport","Deadline pressure, CDC/reset and underrun checks", "integration", "Integration planned")
    for x,y in [(325,185),(350,315),(375,445)]:
        d.wire([(x,y),(430,y),(430,270),(480,270)])
    d.wire([(725,270),(820,270)],"candidates",(730,255))
    d.wire([(948,390),(948,320)],"objects",(963,359))
    d.wire([(1075,270),(1090,270),(1090,540),(603,540),(603,575)],"selected pixel",(685,530))
    d.wire([(725,625),(820,625)],"RGB",(750,611),kind="integration")
    d.note(45,589,"depth is a scroll relationship")
    d.note(45,610,"every active plane costs fetch service")
    d.note(45,631,"scanout has a fixed service deadline")
    diagrams.append(d)

    d = Diagram("geometry", "Basic 3D · prepare, cover, fill", "Proposed flat-shaded path · CPU geometry setup and painter ordering first", 720)
    d.node("cpu",45,150,280,"CPU scene preparation","Transform / project / clip / order","The CPU owns scene state, near-plane clipping and painter ordering, using arithmetic assistance where useful.","Mesh/scene state and math responses","Clipped, ordered screen-space triangles","Bounded scene setup and near-plane tests", "reused", "CPU role / software pending")
    d.node("math",420,150,280,"Fixed-point math unit","Multiply / accumulate / divide","Define signedness, widths, rounding, overflow and divide-by-zero. Pipeline/cycle costs are not yet allocated.","Math request operands and operation","Result, status and completion","Independent integer extrema and stall tests")
    d.node("setup",795,150,280,"Triangle setup","Bounds + oriented edge equations","Generate coefficients and a clipped bounding box with an explicit winding and degeneracy contract.","Triangle coordinates, flat color and band","Edges, bounds and starting values","Shared-edge, degenerate and coordinate-extrema cases")
    d.node("coverage",795,385,280,"Coverage walker","Increment edges by A / B","Evaluate the selected sample/edge inclusion rule without overflow; reject samples outside the triangle.","Edge state and bounding box","Covered destination positions","Integer reference coverage, all windings and edges")
    d.node("fill",420,385,280,"Flat fill + write queue","No texture fetch in version one","Emit color/priority for covered pixels. Preserve position and state across backpressure.","Coverage positions and flat color/band","Queued memory writes","Stalls at any pixel without duplicated coverage")
    d.node("memory",45,385,280,"Shared memory service","Triangles contend with other draws","Schedule writes alongside sprites, tiles, CPU and display. Covered-pixel throughput depends on the combined scene.","Fill write requests and byte lanes","Write completions and latency counters","Contended workload meets its explicit frame budget", "integration", "Budget / integration open")
    d.node("done",45,565,280,"Fence + counters","Measure setup and fill separately","Completion includes outstanding writes; count rejected samples and memory stalls separately from CPU geometry time.","Write ACKs, command boundaries and counters","Done/IRQ and useful performance evidence","No early fence; report bounded representative scenes",h=90)
    d.wire([(325,200),(420,200)],"math",(345,186),both=True)
    d.wire([(185,150),(185,110),(935,110),(935,150)],"screen-space command",(450,103))
    d.wire([(935,250),(935,385)],"edge state",(950,320))
    d.wire([(795,435),(700,435)],"covered XY",(704,420))
    d.wire([(420,435),(325,435)],"writes",(345,420),kind="integration")
    d.wire([(185,485),(185,565)],"commit ACK",(200,532),kind="integration")
    d.note(420,593,"E(x+1, y) = E(x, y) + A")
    d.note(420,615,"E(x, y+1) = E(x, y) + B")
    d.note(420,637,"No first-version Z buffer, textures or alpha")
    diagrams.append(d)

    d = Diagram("memory", "Memory service · bounded queues and explicit completion", "Proposed scheduler · x32 controller/loader/cache service checks pass; full display timing remains open", 760)
    clients = [("display",135,"Display / line fill","Deadline-sensitive reads"),("draw",270,"Sprite + triangle writes","Queue pressure must stall"),("cpu",405,"CPU / cartridge access","Preserve visible behavior"),("load",540,"Image / asset loading","Game reset and ownership")]
    for key,y,title,sub in clients:
        d.node(key,45,y,280,title,sub,"Each client holds coherent requests under backpressure and tracks accepted work until completion. Its service policy must be tested under contention.","Client address/data/byte lanes and validity","Queued requests, later data/completion","Exactly-once service and bounded client-specific latency", "integration", "Interface / policy proposed",h=90)
        d.wire([(325,y+45),(405,y+45),(405,330),(510,330)])
    d.node("policy",510,130,245,"Service policy","Reserve display; bound starvation","Refresh and scanout deadlines coexist with CPU/cart latency and draw queues. The exact priority/fairness policy remains open.","Queue levels, deadlines and refresh age","Arbitration decisions and service counters","Worst-case latency and no unbounded starvation",h=100)
    d.node("arbiter",510,280,245,"Request arbiter","Accept once; tag responses","Select coherent requests and associate each response with its owner. Outstanding depth is a design choice.","Per-client queues and policy","Accepted controller request, routed ACK/data","Randomized contention; no lost or duplicate request",h=130)
    d.node("controller",845,280,245,"SDRAM controller","Init / activate / access / recover","The Tang controller/loader/cache path passes independent command-model checks. A separate enhanced elastic arbiter/controller now also passes blitter contention workloads. A deadline-reserved scheduler and complete enhanced board timing remain open.","Request, address, data and byte mask","Memory commands, response and ready status","Bank/row/column, byte lanes, latency and bus direction", "integration", "Command-model checks passed",h=130)
    d.node("refresh",510,545,245,"Refresh + readiness","Progress even under load","Hardware maintains memory service requirements independently of firmware or a well-behaved game.","Clock/reset and refresh accounting","Refresh requests and initialization state","Refresh deadline pressure and reset/startup sequence", "integration", "Command-model checks passed",h=100)
    d.node("sdram",845,545,245,"8 MiB x32 SDRAM","Existing Tang board memory","The physical organization belongs to the board; a raw bus transfer rate is not useful scheduled throughput.","SDRAM clock, command, address, DQM and DQ","Stored data and read bus","Controller model plus later physical acceptance", "integration", "Physical device / port pending",h=100)
    d.wire([(633,230),(633,280)],"policy",(649,261))
    d.wire([(755,315),(845,315)],"request",(766,301))
    d.wire([(845,375),(755,375)],"response",(761,395),kind="integration")
    d.wire([(968,410),(968,545)],"DQ / commands",(980,480),kind="integration",both=True)
    d.wire([(755,595),(790,595),(790,445),(915,445),(915,410)],kind="integration",dashed=True)
    d.note(45,680,"Client queues and response tracking are logical; depths and outstanding counts are not fixed here.")
    diagrams.append(d)

    d = Diagram("graphics-memory", "Enhanced memory · accept, issue, retire", "Implemented elastic arbiter + auto-precharge controller · model evidence, no full-system timing claim", 720)
    d.node("clients",45,140,270,"Three request clients","Host / blitter / front-read test","Each client holds coherent fields until valid and ready accept the request. Test front reads are synthetic; native scanout and CPU integration remain ahead.","Three valid/address/data/mask bundles","Accepted ownership and later response","Single outstanding work, input changes after accept and no stale replies",state="Contention checks pass")
    d.node("slot",425,140,270,"Elastic request slot","Bypass ready; retain stalled work","Forward directly when the controller is ready. Otherwise latch the accepted request and hold it through recovery, refresh or initialization without replacing its fields.","Round-robin selected request and controller ready","Stable controller request and saved owner","Bypass plus held request, 900-cycle stall and reset cancellation",state="Backpressure checks pass")
    d.node("control",805,140,270,"SDRAM command FSM","ACT / wait / READ or WRITE","Use the same conservative 64 MHz geometry, CAS and auto-precharge rules as the project legacy controller. Write ACK follows physical WRITE; bank recovery still blocks the next ACTIVATE.","Aligned word request and byte enables","Registered commands, captured data and ACK","Unchanged independent pin model, masks, bank boundaries and bus direction",state="Pin-model checks pass")
    d.node("round",45,370,270,"Round-robin grant","Rotate after every acceptance","Continuous demand rotates 0, 1, 2. This is fairness, not a display-deadline reservation policy; new combined workloads still require explicit latency evidence.","Client validity and next-owner pointer","One selected client and ready bit","6,000 continuous requests with strict grant order and bounded response",state="Fairness checks pass")
    d.node("reply",425,370,270,"Response ownership","Retire old; accept next on edge","Route the old data/token to its saved owner while the next request can enter the slot on that same edge. Unexpected replies set a sticky protocol fault.","Saved owner, controller ACK and next request","Correct client response and reusable slot","Exactly-once physical operation before ACK; simultaneous turnover and fault recovery",state="Ownership checks pass")
    d.node("pins",805,370,270,"x32 SDRAM interface","CAS 2 / burst 1 / auto-precharge","Four banks, 2048 rows and 256 word columns. The software pin model checks command timing and DQ conflicts; it does not establish board setup/hold or physical signal quality.","Command/address, DQM, DQ and clock","Stored word or CAS-delayed read data","Physical phase, signal integrity and real-board diagnostics", "integration", "Physical output unqualified")
    d.node("refresh",805,555,270,"Recovery + refresh","Progress while clients wait","Keep tRCD, tRP and tWR at two clock edges and tRFC at five at 64 MHz. Refresh has priority at idle boundaries, even with a queued client or injected controller stall.","Recovery state and refresh age","Safe ready and periodic refresh commands","No early ACTIVATE/refresh, 200 us startup and refresh under load",state="Timing-model checks pass",h=100)
    d.wire([(315,190),(425,190)],"accept",(342,177))
    d.wire([(695,190),(805,190)],"issue",(728,177))
    d.wire([(940,240),(940,370)],"commands / DQ",(954,312),kind="integration",both=True)
    d.wire([(805,220),(755,220),(755,320),(560,320),(560,370)],"read / ACK",(635,307))
    d.wire([(425,420),(315,420)],"next owner",(330,406))
    d.wire([(180,370),(180,300),(560,300),(560,240)],"grant",(370,287))
    d.wire([(560,370),(560,340),(400,340),(400,220),(425,220)],"reuse slot",(416,327))
    d.wire([(940,555),(940,470)],"recovery",(956,519))
    d.note(45,584,"A write ACK is distinct from bank readiness.")
    d.note(45,608,"The next ACTIVATE still waits for safe recovery.")
    d.note(45,632,"Legacy memory RTL and board image are unchanged.")
    diagrams.append(d)

    d = Diagram("frames", "Frame presentation · ownership from capture to scanout", "Same-clock capture checks pass · display reader, CDC and board integration remain open", 740)
    d.node("free",45,310,240,"Free bank","No display or pending writer","A bank is allocatable only when no active writer, queued write or display owner can still reference it.","Released ownership and drained work","One allocated source-frame bank","No allocation while old writes or reads remain", "integration", "Capture simulation passes",h=110)
    d.node("writing",365,150,280,"Writing candidate","Capture emitted RGB samples","Keep a coherent bank for a whole incoming frame. Count pending memory writes and invalidate on overflow/truncation.","Source pixels, addresses and queue capacity","Writes, pending count and candidate validity","Backpressure/overflow cannot publish a partial frame", "integration", "Capture simulation passes",h=110)
    d.node("complete",800,150,280,"Completed candidate","Frame end AND pending = 0","Only a whole valid frame with every accepted write committed can become the next presentation candidate.","End-of-frame, validity and write ACKs","Ready bank token","Final write ACK and frame-end race cases", "integration", "Capture simulation passes",h=110)
    d.node("display",800,450,280,"Displayed bank","Swap only at safe boundary","Keep display ownership stable through scanout. Repeat an existing frame when a new complete one is not ready.","Completed token and display frame boundary","Stable read bank; released previous bank","Safe-boundary and reader/CDC checks; full board timing still open", "integration", "RGB integration passes",h=110)
    d.node("invalid",365,450,280,"Invalid candidate","Drain before reuse","An incomplete/overflowed frame cannot be displayed. Its remaining accepted writes must be accounted for before reuse.","Overflow/truncation status and pending writes","Safe release after drain","Overflow at first/last pixel and reset races", "integration", "Capture simulation passes",h=110)
    d.wire([(285,350),(325,350),(325,205),(365,205)],"allocate",(235,288))
    d.wire([(645,205),(800,205)],"all writes ACKed",(665,191))
    d.wire([(940,260),(940,450)],"vblank handoff",(955,360))
    d.wire([(505,260),(505,450)],"invalid frame",(520,360),kind="integration")
    d.wire([(365,505),(315,505),(315,390),(285,390)],"drained",(222,489),kind="integration")
    d.wire([(940,560),(940,640),(165,640),(165,420)],"release previous displayed bank",(420,628))
    d.note(45,105,"Three physical banks can hold different roles; these boxes are states, not five allocated buffers.")
    diagrams.append(d)

    d = Diagram("native-commands", "Native commands · CPU to graphics and back", "Implemented experimental v1 · real CPU ROM and dual-clock model checks, no full board timing claim", 720)
    d.node("cpu",45,140,270,"Native R65C02 + ROM","Local instruction / working memory","The actual pinned CPU executes original ca65 diagnostic code, uploads asset bytes, submits commands, checks results and handles IRQ. RDY stays high; external-memory CPU stalls are not implemented here.","Local ROM/RAM and completion IRQ","Eight-bit register writes and reads","Cold/warm original ROM with no host asset uploads", "reused", "CPU ROM checks pass")
    d.node("shadow",425,140,270,"Staging + control","36 bytes / one submitted command","CPU writes edit staging bytes. GO atomically copies them only when available. Duplicate GO sets rejection without replacing the accepted tag or payload.","CPU-local address/data/write strobe","Immutable submitted descriptor and request toggle","Busy/held-result rejection, shadow poisoning and control races",state="MMIO checks pass")
    d.node("request",805,140,270,"Command mailbox","Held data / synchronized toggle","Synchronize the request toggle, then capture the stable descriptor in the graphics domain. The common reset must run with both clocks active; physical bundled-data timing still needs review.","Submitted descriptor and request toggle","Graphics-owned descriptor and operation","Three clock ratios/phases, joint reset and no duplicate command",state="Digital CDC checks pass")
    d.node("engine",805,365,270,"Draw / fill dispatch","Validate then run custom blitter","Validate serialized reserved bits before launching the independently tested engine. Draw/fill errors and counters become one result only after the final memory ACK.","Validated operation and engine completion","Tagged result or byte-port operation","Exact samples, clipping, coverage, errors and final fence",state="CPU pixel checks pass")
    d.node("result",425,365,270,"Held result mailbox","Tag / data / six counters","Hold one coherent result while its reply toggle crosses to the CPU. Keep it until CPU acknowledgment returns; no byte-by-byte live counter sampling is needed.","Graphics result and synchronized acknowledgment","Stable CPU result payload and reply toggle","No tearing, held result, reset cancellation and ACK before reuse",state="Result checks pass")
    d.node("status",45,365,270,"CPU status + IRQ","Done / reject / fault / ready","Latch the whole reply into CPU-domain registers. Done, rejection or fault assert level IRQ when enabled. Reads have no side effects; explicit control writes acknowledge or clear.","Synchronized reply, readiness and fault","Coherent reads and CPU interrupt","Actual CPU handler, six IRQ acknowledgments and reset recovery",state="IRQ checks pass")
    d.node("memory",805,555,270,"Graphics memory clients","Blitter words + CPU byte access","Two clients share the enhanced elastic service with synthetic front reads. CPU byte commands upload assets and select one x32 lane. Native display ownership and scanout remain separate work.","Masked requests and returned memory words","Committed writes and selected read byte","Real SDRAM model, byte lanes and complete storage equality", "integration", "Memory-model checks pass",h=100)
    d.node("ack",45,555,270,"Explicit acknowledgment","No automatic read-side clear","ACK releases Done and returns a toggle to the graphics side. ACK+GO cannot reuse a held result in one write. New completion/rejection wins over a simultaneous clear.","CPU control bits and held result state","Reusable mailbox and deasserted IRQ","Control combinations, IRQ levels and immediate next submission",state="Protocol checks pass",h=100)
    d.wire([(315,190),(425,190)],"MMIO",(348,177))
    d.wire([(695,190),(805,190)],"publish",(724,177))
    d.wire([(940,240),(940,365)],"capture",(956,306))
    d.wire([(805,415),(695,415)],"completion",(710,401))
    d.wire([(425,415),(315,415)],"reply",(345,401))
    d.wire([(180,365),(180,240)],"read / IRQ",(194,306))
    d.wire([(940,555),(940,465)],"request / ACK",(957,514),kind="integration",both=True)
    d.wire([(180,465),(180,555)],"control",(195,520))
    d.wire([(315,600),(560,600),(560,465)],"return ACK",(404,585))
    d.note(425,637,"CPU clock and graphics clock are distinct.")
    diagrams.append(d)

    d = Diagram("boot", "System control · configure circuits, then run code", "Proposed monitor path · self-contained mode switching and boot mapping remain open", 800)
    d.node("config",45,145,270,"FPGA configuration","Bitstream creates the circuits","The bitstream defines CPU and peripheral hardware. It is distinct from executable system firmware and game data.","Configuration storage/programming flow","Configured logic and reset state","Reproducible complete bitstream and safe startup", "integration", "Board build pending")
    d.node("safe",425,145,270,"Clock / memory readiness","Hardware-controlled safe state","Establish reset, legal clocks and memory initialization. Continuous refresh cannot rely on game software.","Clock lock, reset and controller status","Readiness, held resets and error status","Delayed readiness, loss/reset and memory startup tests", "integration", "Integration planned")
    d.node("monitor",805,145,270,"Local boot monitor","65C02 system ROM + local RAM","Proposed original firmware provides diagnostics, loading and recovery. Current native ROM boots directly to its game.","Safe boot state and status registers","Load/control commands and diagnostics","Original monitor boots and can recover from a hung game",state="Proposed / not implemented")
    d.node("load",805,380,270,"Load image","Validate before accepting launch","Receive the whole image with address/length/integrity checks while game memory is owned by the loader.","Serial/storage payload and declared metadata","Verified writes and candidate image state","Corrupt/truncated/reset-mid-load tests", "integration", "Loader service checks passed")
    d.node("commit",425,380,270,"Commit gate","Every required write completed","Image validity and required BIOS/core state must be satisfied before a single launch event can occur.","Image metadata, CRC/length and write ACKs","Committed image and launch eligibility","Repeated/failed commit and final-write race tests")
    d.node("handoff",45,380,270,"Mode + reset handoff","Native / legacy boundary","Restore the correct map and timing. Separate bitstream switching is an unresolved mechanism, not implemented multiboot.","Committed image, selected mode and core readiness","Defined reset release or future mode transition","Specify and verify the exact mechanism before use", "integration", "Mechanism open")
    d.node("game",45,625,270,"Game runtime","Use the selected machine ABI","Games execute on the console CPU after a controlled handoff. They initialize their own working state.","Correct reset vector, map and image","Gameplay and hardware requests","Original diagnostic and named runtime acceptance", "reused", "Runtime boundary",h=90)
    d.node("recovery",805,625,270,"Recovery / diagnostics","Remain reachable after failure","Report load/readiness errors and provide a reliable restart path. Persistent update policy is still open.","Error status, user reset or failed launch","Safe recovery state and diagnostic result","Failed image and hung-game recovery tests", "integration", "Proposed recovery path",h=90)
    d.wire([(315,195),(425,195)],"configured",(328,181),kind="integration")
    d.wire([(695,195),(805,195)],"safe boot",(710,181),kind="integration")
    d.wire([(940,245),(940,380)],"load request",(954,320))
    d.wire([(805,430),(695,430)],"verified data",(698,414))
    d.wire([(425,430),(315,430)],"valid commit",(321,414))
    d.wire([(180,480),(180,625)],"release",(195,554),kind="integration")
    d.wire([(560,480),(560,545),(940,545),(940,625)],"failure / reset",(650,534),kind="integration",dashed=True)
    d.note(425,656,"Bitstream != system ROM != game image")
    d.note(425,679,"ROM size and final boot/storage format are open")
    diagrams.append(d)

    d = Diagram("legacy", "Lynx mode · retain the console, adapt its surroundings", "Pinned upstream CPU / Suzy / Mikey · source cadence independent of display cadence", 860)
    d.zone(25,110,655,440,"RETAINED CONSOLE / SCOPED DIAGNOSTIC + CORE ROUTE EVIDENCE")
    d.node("cpu",55,165,245,"Upstream Lynx CPU","Original-visible execution", "Keep the CPU implementation from the pinned Lynx source. Native R65C02 functional tests do not certify this different implementation.","Original bus, interrupts, reset and clock enable","Original CPU bus activity","Broader timing/IRQ/game cases and physical evidence", "reused", "Scoped core evidence")
    d.node("ram",395,165,245,"64 KiB local work RAM","Adapted inferred dual-port RAM","Our explicit own-port forwarding adapter matches defined Intel-model observations; undefined mixed-port collision cases were excluded.","Core and loader RAM accesses","RAM results with defined enables/forwarding","Primitive-level and integrated/hardware acceptance", "reused", "RAM-model check passed")
    d.node("suzy",55,365,245,"Suzy graphics + math","Original sprite/collision behavior","Reused console graphics and arithmetic logic. The existing diagnostic exercises a multiply, not the full sprite/RLE/collision feature set.","CPU-visible state, commands and memory data","Original graphics/math/collision behavior","Focused sprite scaling/RLE/collision and math corpus", "reused", "Scoped diagnostic only")
    d.node("mikey",395,365,245,"Mikey DMA + timers","RGB emission, audio and IRQs","Reuse original timer/display/audio logic. Emitted RGB must be captured at its original palette state.","Original RAM/timers, palette and controls","RGB pixel writes, audio, interrupts","Timer/IRQ/audio and palette-effect comparisons", "reused", "Scoped diagnostic only")
    d.node("cart",780,165,295,"Cartridge + BIOS loader","New storage / original interface","Original UART/loader/cart/cache service checks pass without MiSTer HPS dependencies. Cold and warm console diagnostics now boot through this path. Broad game compatibility remains untested.","Owner image data and core read requests","BIOS upload, image writes and cart results","Integrated recovery plus broad game/header acceptance", "integration", "Service checks passed")
    d.node("capture",780,365,295,"Capture emitted RGB444","Keep palette changes in time","Store the core's actual colors. Reconstructing an entire frame with one final palette would lose mid-frame effects.","Original pixel address/color events","Padded RGB presentation writes","Pixel-exact source comparison; broader palette-effect corpus still needed", "integration", "RGB integration passes")
    d.node("frames",780,555,295,"Complete-frame presentation","SDRAM + ownership + line buffers","Decouple source cadence from display transport; whole-frame repeat/drop is allowed while execution remains faithful.","Committed frame data and ownership tokens","Stable scanout samples","Whole-frame/line, overload and CDC checks; physical timing open", "integration", "RGB integration passes")
    d.node("display",780,715,295,"Exact legacy replication","2x logical / no added borders","Each 160x102 source pixel becomes a 2x2 block filling the 320x204 logical screen edge to edge. Current bench-transport padding is not the accepted handheld presentation.","Source RGB and display timing","Complete border-free logical image","All source edges, exact 2x and final visible-area qualification", "integration", "Logical pass / panel open",h=80)
    d.wire([(300,215),(395,215)],"local bus",(310,201),kind="reused",both=True)
    d.wire([(178,265),(178,365)],"MMIO",(194,323),kind="reused")
    d.wire([(300,245),(345,245),(345,415),(395,415)],kind="reused")
    d.wire([(300,395),(325,395),(325,285),(518,285),(518,265)],kind="reused")
    d.wire([(518,365),(518,265)],"DMA",(535,324),kind="reused")
    d.wire([(780,215),(710,215),(710,145),(335,145),(335,215),(300,215)],kind="integration")
    d.wire([(640,415),(780,415)],"pixels",(675,401),kind="integration")
    d.wire([(928,465),(928,555)],"writes / ACK",(945,513),kind="integration")
    d.wire([(928,655),(928,715)],"owned frame",(944,693),kind="integration")
    logic = evidence["post_route_with_test_harness"]["LUT4"]
    d.note(55,617,f"Core-only route: {logic['used']:,} / {logic['available']:,} LUT sites")
    d.note(55,641,"33 / 46 BSRAM | partial timing models")
    d.note(55,665,"Board services at right are outside that result")
    d.note(55,702,"Zero commercial Tang games tested")
    d.note(55,726,"No physical Tang acceptance yet")
    diagrams.append(d)

    d = Diagram("scanout", "Legacy scanout · two clocks, explicit ownership", "Implemented RGB path · component and real-console simulation pass; board timing remains open", 870)
    d.zone(25,110,510,540,"SYSTEM CLOCK / 64 MHz")
    d.zone(585,110,510,540,"PIXEL CLOCK / NOMINAL 25.2 MHz")
    d.node("frame",55,155,430,"Complete-frame owner","Capture bank stays immutable while displayed","The scanout requests a frame handoff only after its previous line reads have completed. Capture either publishes the latest completed bank or retains the current one.","Safe present pulse, completed capture bank","Stable display-bank snapshot","Never read a writing bank or write the displayed bank",state="Integration simulation passes")
    d.node("reader",55,330,430,"80-word line reader","One accepted read, then its response","Read two padded RGB444 pixels per SDRAM word. A line is acknowledged only after all 80 words are stored in its target buffer.","Held line/buffer request, display-bank snapshot","80 memory reads, completed-line ACK","Delayed acceptance/response, address and lane tests",state="Integration simulation passes",h=110)
    d.node("memory",55,510,430,"Round-robin memory service","Cart / capture / line-read clients","A registered single-outstanding arbiter tags ownership and holds request fields stable through controller refresh or backpressure. The controller continues refresh independently.","Three client requests and SDRAM responses","Exactly-once tagged service","Contended reads/writes and reset cancellation",state="Command-model checks passed")
    d.node("mailbox",635,155,410,"Line request / completion mailbox","Stable metadata + synchronized toggles","Pixel-side line/buffer/frame metadata stays unchanged until acknowledgment. Each crossing uses a two-register toggle synchronizer. Independent unilateral resets are not supported.","Timing position, free buffer and completed-line ACK","Held request plus coherent completion ownership","Different clock ratios/phases and joint reset",state="CDC simulation passes")
    d.node("buffers",635,330,410,"Two 80-word line buffers","System writes; pixel port reads","Alternate banks by source-row parity. Row N+2 may reuse N's bank only after both output copies of N finish. Validity gates unknown RAM data.","Committed line words and acknowledged bank metadata","Synchronous pixel-port word","No read/refill overlap; one mapped block RAM",state="RAM mapping + simulation pass",h=110)
    d.node("scale",635,510,410,"Exact 2x RGB444 replication","One source sample becomes four pixels","Use source X/2 and Y/2 on the centered 320x204 canvas. Decide readiness before a row pair; late data cannot reveal half a row. An underrun blanks the pair and increments a counter.","Line word, source parity and latched pair validity","RGB444 samples or a complete black row pair","All 65,280 canvas pixels; deliberate stalls and recovery",state="Pixel comparisons pass")
    d.node("timing",55,705,430,"Current 640x480 bench transport","800x525 total pixels / negative sync","Existing timing tests cover a centered 320x204 window at (160,138). The owner requires no borders in the final visible game area; this bench padding is historical harness behavior, with its replacement policy pending.","Independent pixel clock and reset","Bench coordinates, DE and sync","Keep current transport evidence separate from final border-free presentation",state="Bench timing passes",h=100)
    d.node("output",635,705,410,"Parallel RGB / timing boundary","Serializer and physical panel remain open","Simulation establishes logical samples and cadence. FPGA I/O, PLL/reset implementation, serializers, board constraints and the handheld panel need their own acceptance.","RGB444, DE, horizontal and vertical sync","Future transport encoder / backlit panel","Full board routing/timing and later physical evidence", "integration", "Board output integration open",h=100)
    d.wire([(270,255),(270,330)],"present / snapshot",(285,295),both=True)
    d.wire([(270,440),(270,510)],"reads / ACKs",(285,480),both=True)
    d.wire([(635,205),(560,205),(560,385),(485,385)],dashed=True,both=True)
    d.wire([(485,405),(635,405)],"line words",(510,425))
    d.wire([(840,255),(840,330)],"owned ACK",(855,295),dashed=True)
    d.wire([(840,440),(840,510)],"samples",(855,480))
    d.wire([(485,755),(605,755),(605,175),(635,175)],dashed=True)
    d.wire([(840,610),(840,705)],"RGB / timing",(855,680))
    d.note(55,681,"Crossing metadata is held until ACK; both reset domains must start together.")
    diagrams.append(d)

    d = Diagram("audio", "Stereo audio · sound generation to serial pins", "Implemented filter / mailbox / I2S · analog fidelity and full board timing remain open", 900)
    d.zone(25,105,1070,230,"SYSTEM CLOCK / 64 MHz")
    d.zone(25,460,1070,220,"AUDIO CLOCK / 12.288 MHz REFERENCE REQUIREMENT")
    d.node("mikey",45,150,270,"Mikey sound + stereo mix","Reused timers / LFSRs / routing","The pinned core produces signed PCM16 left/right values. The original CPU diagnostic configures two independent channel timers; host code does not create the tone.","Original sound registers and core timing","Signed stereo values in the system domain","Original timer/routing diagnostics and later game corpus", "reused", "Real-core diagnostic passes",h=110)
    d.node("filter",425,150,270,"Four-pole fixed-point filter","Q16 state / signed shift-add","Four registered poles per channel smooth high-rate core values. Opposite full-scale subtraction uses 33 bits; rounding and negative shifts have explicit rules. The bench response is provisional.","Signed stereo values, enable and reset","Filtered PCM16 stereo pair","Wide-arithmetic model, signed extremes and measured transfer function",state="Component checks pass",h=110)
    d.node("snapshot",805,150,270,"Coherent stereo snapshot","Latch both channels on one edge","A synchronized pull request latches left and right together. Held data remains unchanged until a later acknowledged request permits replacement.","Filtered pair and synchronized request toggle","Stable pair and acknowledgment toggle","No mixed-generation left/right pair; held-data ownership",state="Clock-crossing checks pass",h=110)
    d.node("clock",45,510,270,"Integer audio clock divider","3.072 MHz BCLK / 48 kHz frames","Divide the separate audio reference by four and use 64 bit clocks per stereo frame. Exact board generation, I/O and clock constraints remain unqualified.","12.288 MHz reference and local reset","Bit edges and frame acceptance timing","Pin cadence and two modeled reference ratios",state="Logical cadence passes",h=120)
    d.node("tx",425,510,270,"Frame latch + I2S serializer","One coherent pair for both slots","Latch once at frame start. Send PCM16 MSB first with the I2S one-bit offset and zero slot padding. Missing data after startup produces a complete silent frame and a sticky counter.","Ready stereo pair, integer bit edges","BCLK / WS / SD and underrun status","Independent pin decoder, signed words, silence and recovery",state="Pin decoding passes",h=120)
    d.node("receive",805,510,270,"Audio-domain holding pair","Acknowledge before consuming","The acknowledgment crosses through two registers before stable stereo metadata is captured. Keep the pair valid until the transmitter accepts it.","Stable held data and synchronized acknowledgment","One ready pair; next pull after consumption","Different phases, stopped source clock and joint reset",state="Clock-crossing checks pass",h=120)
    d.node("stereo",45,740,270,"Stereo headphone / line path","Output circuit still to be chosen","The FPGA retains separate channels. Final DAC/codec, amplification, connectors, power and audible response require a qualified stereo circuit.","I2S stereo and qualified clocks/power","Future stereo analog output","Part/interface choice, schematic and physical measurements", "integration", "Physical circuit open",h=100)
    d.node("mono",805,740,270,"Onboard mono amplifier","Existing MAX98357A interface","The board amplifier accepts serial input and provides mono amplification. Wiring, mode, enable sequencing, clock quality and actual speaker output need physical acceptance.","I2S stream, board power and enable","Mono speaker output","Board constraints and physical audio observations", "integration", "Physical acceptance open",h=100)
    d.wire([(315,205),(425,205)],"PCM16",(344,191),kind="reused")
    d.wire([(695,205),(805,205)],"filtered",(716,191))
    d.wire([(940,260),(940,510)],"held pair / toggles",(950,392),dashed=True,both=True)
    d.wire([(805,570),(695,570)],"one pair",(718,555))
    d.wire([(315,570),(425,570)],"bit edges",(330,555))
    d.wire([(560,630),(560,700),(180,700),(180,740)],"stereo route",(275,689),kind="integration")
    d.wire([(560,700),(940,700),(940,740)],"mono route",(705,689),kind="integration")
    d.note(425,778,"Both reset domains assert together.")
    d.note(425,800,"No physical output is certified here.")
    diagrams.append(d)

    d = Diagram("clocks", "Clock islands · one machine, three reference inputs", "Board-wrapper design · ideal-clock control tests do not qualify PLLs or electrical timing", 980)
    d.zone(25,110,1070,130,"REQUIRED MS5351 REFERENCE PROFILE / NOT MEASURED ON A BOARD")
    d.node("sysref",45,145,270,"System reference","O0 / 64 MHz", "The external generator must supply this frequency before memory and the original console run. This design does not program that generator.","Configured oscillator output","64 MHz reference","Verify generator configuration and actual frequency", "integration", "Required reference",h=80)
    d.node("videoref",425,145,270,"Video reference","O1 / 25.2 MHz", "The independent video reference is not assumed phase-aligned to the system or audio clock.","Configured oscillator output","25.2 MHz reference","Verify generator profile, input pin and jitter", "integration", "Required reference",h=80)
    d.node("audioref",805,145,270,"Audio reference","O2 / 12.288 MHz", "A separate integer-related reference allows exactly 64 bit clocks per stereo frame at 48 kHz.","Configured oscillator output","12.288 MHz audio clock","Measure reference rate and stopped-clock recovery", "integration", "Required reference",h=80)
    d.node("syspll",45,330,270,"System PLL + phase output","64 MHz / shifted memory clock", "The rPLL wrapper maps and packs at the required frequency ratio. Its half-period-shifted SDRAM clock still needs phase and I/O timing qualification.","64 MHz reference, button reset","System clock, SDRAM clock, lock","Generated-clock phase and SDRAM I/O timing", "integration", "Packed / phase open",h=115)
    d.node("videopll",425,330,270,"Video PLL + divide by five","126 MHz / 25.2 MHz", "The 5x PLL and divide-by-five graph is checked against the mapped netlist and accepted by the packer. Serializer alignment and clock phase need separate acceptance.","25.2 MHz reference, reset and locks","126 MHz FCLK, 25.2 MHz PCLK, lock","PLL limits, divider/serializer alignment and routed timing", "integration", "Packed / phase open",h=115)
    d.node("audiodiv",805,330,270,"Audio reference distribution","Direct 12.288 MHz / no audio PLL", "The mailbox and formatter use the audio reference directly. Formatter counters generate BCLK pin edges and frame events; BCLK is not a new clock for internal logic. Board clock routing remains unqualified.","12.288 MHz reference","Same reference for audio-domain logic","Clock input routing and actual reference quality", "integration", "Clock routing unqualified",h=115)
    d.node("system",45,560,270,"Console + shared memory","Local reset / system domain", "Console, loader, arbiter and SDRAM controller run together. Pixel and audio ownership cross through defined held-data handshakes.","System clock, reset, held requests","Execution, memory service and status","Real-console diagnostics plus full-board timing",state="Portable integration passes",h=110)
    d.node("pixel",425,560,270,"Scanout + TMDS symbols","Pixel logic / DDR output primitive", "Owned lines feed RGB and sync. Registered encoders form data words; dedicated serializers need the faster related clock.","Owned lines, pixel and serial clocks","Parallel symbols and future serial pins","Exact pixels, encoding and later board acceptance",state="Pixels + encoding pass",h=110)
    d.node("audio",805,560,270,"Stereo mailbox + output","Independent audio domain", "Held stereo data crosses with synchronized request/acknowledge toggles. A system watchdog requires periodic frame activity before amplifier enable.","Held pair, audio clock, local reset","I2S, frame activity and readiness","Stereo coherence, reset, stopped clocks and amplifier gating",state="Logical transport passes",h=110)
    d.node("reset",45,775,1030,"Joint assertion · local three-edge release","Button or either lost PLL lock asserts reset; each domain waits for its own clock", "Reset asserts asynchronously across all domains and releases after three local rising edges. A stopped domain cannot release its own reset. Metastability, reset recovery and clock quality require implementation review.","Button, PLL locks, clocks and audio frame toggle","Three local resets and guarded amplifier enable","Delayed locks, stopped clocks, lock loss, restart and physical recovery",state="Control RTL tested",h=100)
    for x in [180,560,940]:
        d.wire([(x,225),(x,330)],"reference",(x+15,282),kind="integration")
        d.wire([(x,445),(x,560)],"local clocks",(x+15,504),kind="integration")
        d.wire([(x,775),(x,670)],"reset",(x+15,741),dashed=True)
    d.note(45,918,"CDC: held payload + synchronized handshake; reference phases may differ.")
    diagrams.append(d)

    d = Diagram("tmds", "Display transport · pixels to differential pairs", "DVI-compatible RGB-only bench path · encoder verified; physical serialization remains open", 800)
    d.node("rgb",45,140,270,"Completed RGB sample","RGB444 + DE + H/V sync", "The tested scanout supplies the centered exact-2x Lynx canvas and black borders. The complete transport raster is 800x525 including blanking.","Owned line buffers and timing","RGB444 and aligned active/control signals","Pixel-exact real-core comparison and raster timing",state="RGB checks pass",h=110)
    d.node("expand",425,140,270,"Repeat each color nibble","RGB444 to RGB888", "Repeat each four-bit channel nibble, equivalent to multiplying by 17. This changes transport representation, not source color depth.","Four bits each of red, green and blue","Eight-bit channel values","All 4096 RGB444 colors and decoded channels",state="Exhaustive mapping passes",h=110)
    d.node("encode",805,140,270,"Three TMDS encoders","Independent running disparity", "Each encoder balances its own stream. Active bytes become ten-bit symbols; blanking carries H/V control on blue and control 00 on the other lanes.","RGB888, active enable and H/V","Blue / green / red ten-bit symbols","Every reachable disparity/byte pair, controls and random transitions",state="Independent model passes",h=110)
    d.node("serialize",805,385,270,"Four OSER10 primitives","D0 first / five-times DDR clock", "The wrapper connects ten bits to each dedicated serializer. Three lanes carry data; the fourth repeats the clock word. The encoder check does not certify primitive behavior or physical waveforms.","Ten-bit words, PCLK 25.2 MHz, FCLK 126 MHz","Three 252 Mb/s data lanes plus clock","Primitive wiring, phase, place/route and physical signal quality", "integration", "Wrapper / unqualified",h=120)
    d.node("pads",425,385,270,"True LVDS output buffers","TLVDS_OBUF / LVDS25 board pairs", "The board's display pairs require true LVDS primitives. The packer rejected emulated LVDS on these sites. Electrical behavior and actual display acceptance remain open.","Four serialized logic signals","Positive / negative clock and data","Constraint coverage, true-LVDS packer checks and measured levels", "integration", "Electrical acceptance open",h=120)
    d.node("connector",45,385,270,"Tang display connector","Fixed 640x480 bench timing", "The proposed bench output sends DVI-compatible video through this connector. HDMI audio packets, EDID negotiation and the final handheld interface remain outside this design.","Qualified clock/data pairs","Fixed-mode digital video","Monitor acceptance and later panel qualification", "integration", "Physical acceptance open",h=120)
    d.node("display",45,620,270,"Monitor now / panel later","Logical scale stays separate", "The bench display supports integration. The backlit handheld panel, connector, power and mechanical fit remain open decisions.","Supported transport and power","Visible image on qualified display","Actual display observations before PCB/case freeze", "integration", "Display choice open",h=100)
    d.node("scope",425,620,650,"What the encoder evidence actually covers","2,304 state/byte cases · 460 active codes · complete 800x525 raster", "An independent model counts emitted ones/zeros for disparity, reconstructs bytes and checks lane mapping. It does not model serializer silicon, cable loss, a receiver or clock jitter.","RTL symbols and independent expectations","Reproducible Nix log and scoped JSON","Keep encoding proof separate from board and physical acceptance",state="Digital encoding verified",h=100)
    d.wire([(315,195),(425,195)],"RGB444",(333,181))
    d.wire([(695,195),(805,195)],"RGB888",(710,181))
    d.wire([(940,250),(940,385)],"10 bits / lane",(952,321))
    d.wire([(805,445),(695,445)],"serial",(720,431),kind="integration")
    d.wire([(425,445),(315,445)],"four pairs",(327,431),kind="integration")
    d.wire([(180,505),(180,620)],"video",(195,567),kind="integration")
    d.note(425,563,"25.2 Mpixels/s x 10 bits = 252 Mb/s per data lane.")
    d.note(425,586,"Audio uses separate I2S; no HDMI audio packets.")
    diagrams.append(d)

    d = Diagram("verification", "Evidence gates · intent to measured hardware", "A passed gate has a scope; no diagram is an implementation or timing report", 670)
    stages = [
        ("contract",45,150,"Interface contract","Behavior before implementation","Specify request/accept, reset, ownership, backpressure and completion semantics.","Requirements and open decisions","Testable contracts and invariants","Document edge cases before stabilizing ABI","project","Per-engine work ahead"),
        ("reference",425,150,"Independent reference","Small integer / pixel models","Define expected sampling, coverage and arithmetic separately from implementation structure.","Explicit formats and rules","Expected pixels, values and traces","Models cover extrema and shared-edge/rounding rules","project","Per-engine work ahead"),
        ("rtl",805,150,"RTL simulation","Stalls, resets, contention","Directed and seeded randomized cases check both data and temporal invariants.","RTL, models, stimulus and assertions","Reproducible behavioral evidence","No lost work, early fences or partial-buffer reads","integration","Existing + future checks"),
        ("physical",45,400,"Physical acceptance","Real clocks, memory and pixels","Run original diagnostics then named owner-supplied game cases. Record setup, hashes, failures and electrical/display findings.","Actual board and reproducible test images","Measured hardware and compatibility record","Named board checks; no inferred commercial support","integration","Deferred / not tested"),
        ("route",425,400,"Integrated place + route","Resources, pins and timing","A real board top includes all controllers and outputs. Check timing-model presence as well as clocks, CDC, I/O and constraint coverage.","Complete mapped configuration and constraints","Timing/resource reports and packed image","Complete coverage; a partial-model pass is insufficient","integration","Board build / timing gaps"),
        ("synth",805,400,"Synthesis + mapping","Actual primitives and RAM use","Inspect inference, latches, clocks and device resources. Synthesis alone does not prove physical fit or clock speed.","Pinned RTL, dependencies and device","Mapped netlist and resource report","Correct memories and an explicit whole-system budget","integration","Legacy baseline exists"),
    ]
    for key,x,y,title,sub,detail,inp,out,gate,kind,state in stages:
        d.node(key,x,y,270,title,sub,detail,inp,out,gate,kind,state,h=120)
    d.wire([(315,210),(425,210)],"rules",(348,196))
    d.wire([(695,210),(805,210)],"oracle",(724,196))
    d.wire([(940,270),(940,400)],"behavior",(955,343),kind="integration")
    d.wire([(805,460),(695,460)],"netlist",(717,445),kind="integration")
    d.wire([(425,460),(315,460)],"image",(350,445),kind="integration")
    d.note(45,595,"Native CPU/game checks and Lynx core-only evidence exist; proposed effects need their own gates.")
    diagrams.append(d)
    return {d.key: d for d in diagrams}


def build_chip_diagrams(out, evidence):
    diagrams = definitions(evidence)
    assets = out / "assets/chips"
    assets.mkdir(parents=True, exist_ok=True)
    data = {}
    for key, diagram in diagrams.items():
        (assets / f"{key}.svg").write_text(diagram.svg())
        data[key] = dict(title=diagram.title, subtitle=diagram.subtitle,
                         nodes={n["key"]: {k: n[k] for k in ["title", "detail", "inputs", "outputs", "gate", "kind", "state"]} for n in diagram.nodes})
    (out / "assets/chip-design-data.js").write_text("window.CHIPBUILDER_CHIPS = " + json.dumps(data, ensure_ascii=False) + ";\n")
    return diagrams


def diagram_figure(diagram):
    key = diagram.key
    return f'''<figure class="chip-diagram" data-chip-diagram="{key}" aria-label="{e(diagram.title)}">
      <div class="chip-figure-heading"><span class="chip-figure-number">DESIGN / {e(key.upper())}</span><span>LOGICAL ARCHITECTURE</span></div>
      <div class="chip-toolbar"><span class="chip-interaction-hint">Inspect a block · scroll to explore</span><div class="chip-zoom" hidden><button type="button" data-zoom="out" aria-label="Zoom out diagram">−</button><output aria-label="Diagram zoom">100%</output><button type="button" data-zoom="in" aria-label="Zoom in diagram">+</button><button type="button" data-zoom="fit">Fit</button></div><a href="assets/chips/{key}.svg" target="_blank" rel="noopener">Open SVG ↗</a><a href="assets/chips/{key}.svg" download="chipbuilder-{key}.svg">Download SVG ↓</a></div>
      <div class="chip-canvas" tabindex="0" aria-label="Scrollable {e(diagram.title)}">{diagram.svg()}</div>
      <div class="chip-inspector" aria-live="polite"><div class="chip-inspector-title"><span class="chip-node-kicker">BLOCK INSPECTOR</span><strong>Select a block to inspect its contract</strong><span class="badge proposed">Design scope</span></div><p class="chip-detail">{e(diagram.subtitle)}. The accompanying text defines limitations and acceptance; these diagrams do not add new hardware evidence.</p><dl class="chip-ports"><div><dt>Inputs</dt><dd data-port="inputs">Select a block</dd></div><div><dt>Outputs</dt><dd data-port="outputs">Select a block</dd></div><div><dt>Acceptance gate</dt><dd data-port="gate">Select a block</dd></div></dl></div>
      <figcaption>{e(diagram.title)}. Colors distinguish project logic, reused implementation and integration work. Each block identifies its implementation state.</figcaption>
    </figure>'''
