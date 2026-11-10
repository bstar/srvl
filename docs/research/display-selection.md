# Display selection

Reviewed: 2026-10-28. Status: **technology shortlist; no qualified panel selected**.

## Requirements and leading direction

The user requires color and a **backlight**, with enhanced games targeting 60 fps.
New games render 320 × 204; legacy games render 160 × 102. A roughly 3.5-inch panel
is a working research assumption, not a fixed enclosure requirement.

The leading technology is a transflective color TFT LCD: it combines ambient-light
reflection with LED backlighting. This offers the outdoor-readable character the
user liked in Playdate while allowing play in darkness. Its appearance, reflected
color, indoor brightness, and motion must be judged on a sample.

Playdate uses a monochrome memory LCD, not electrophoretic e-paper. Its official
SDK specifies 30 fps default and 50 fps maximum. Sharp's 3.54-inch LS035Q7DD01
color memory LCD has 320 × 240 resolution and 64 colors, but its documented
18 Hz update rate does not meet the 60 fps goal. A frontlit reflective screen is
not the backlit solution currently requested.

## Shortlist

| Candidate | Verified characteristics | Remaining concerns |
|---|---|---|
| All Shore ASI-T-3501RA1EN/A | 3.5-inch, 480 × 640, transflective, six-LED backlight, 18-bit RGB, 262K colors, 120 nits; 30 ms typical / 50 ms maximum combined rise/fall response | First evaluation lead, not a procurement selection. Confirm exact 60 Hz timing, current availability, price, lifecycle and sample motion quality. Datasheet revisions date to 2014–2015. |
| Densitron DMT035QVNXNT0-1C | 3.5-inch, 240 × 320, transflective, six-LED backlight, RGB/MCU/SPI, 120 nits; 35 ms typical combined rise/fall response | Confirm exact refresh setup, sample availability and motion. Datasheet lists narrow viewing angles in transmissive mode. |
| Leadtek LTK035BFBLM48-V0 | 3.5-inch, 480 × 640, transflective, MIPI, 135 nits | Refresh, response, controller details, availability and price unverified. MIPI adds interface complexity. |
| Toppan COM35H3R12ULC | 3.5-inch, 480 × 640, RGB, backlit Blanview; 54–66 Hz recommended VSYNC, 60 Hz typical | Manufacturer exit and 100 ms maximum combined rise/fall response make this unattractive as a new-design foundation. |

Other leads: Maclight MLT035Q45-R9 is a 240 × 320 ILI9341 transflective module
with LED backlight. Phoenix PDI350MTQI-02 is another QVGA transflective listing.
Neither has been qualified for refresh, motion, or procurement.

## Lifecycle and documentation findings

Toppan's April 2026 manufacturer notice sets the last-time-buy deadline at the
end of October 2026 and final deliveries/business discontinuation at the end of
March 2028. This affects the Blanview/ORTUSTECH supply path. Do not infer continued
availability from an unchanged product catalog.

Focus E35RB-FW115-N is marked not recommended for new designs and out of stock.
Its suggested replacement, E35RB-B-RW600-N, has inconsistent descriptions: the
product page says transmissive/Blanview, while its PDF says transflective. Its
actual optical construction and source require clarification before selection.

## Refresh versus motion

A 60 Hz input accepts a new frame every 16.7 ms. Pixel response describes how
quickly the LCD changes optical state. A panel can accept 60 Hz yet smear moving
sprites. Combined black/white rise-plus-fall timings are not interchangeable with
individual gray-to-gray timings, nor should their reciprocal be called a frame
rate. Cold-temperature response can be worse.

Acceptable motion has not been proven for any shortlisted panel. Do not promise
clear 60 fps gameplay based on the interface rate alone.

## Resolution and integration

| Landscape panel area | Enhanced image | Legacy image | Borders |
|---|---|---|---|
| 320 × 240 | 320 × 204, native | 160 × 102 at 2× | 18 rows above/below |
| 640 × 480 | 320 × 204 at 2× | 160 × 102 at 4× | 36 rows above/below |

These preserve square pixels and aspect ratio. Physical LCD resolution does not
require the game to render a larger framebuffer. A conventional backlit IPS panel
such as EastRising ER-TFT035-7 is a fallback; it is not a qualified transflective
replacement and its exact timing/motion also needs validation.

The portrait 480 × 640 and 240 × 320 candidates must be mounted sideways for our
landscape image. Account for scanout rotation, controller address modes, memory
access order, subpixel layout, viewing angles, flex cable position and connector
clearance. Simple streaming line replication alone does not solve arbitrary
portrait-to-landscape scan conversion.

Prefer parallel RGB for our own display controller if an appropriate panel is
available. SPI may configure the panel while RGB carries pixels; an SPI listing
does not mean full-screen video should use SPI. Backlights require a suitable
constant-current driver; six series LEDs can require a boosted voltage around
17–21 V, not a direct GPIO or battery connection. Evaluate actual system power.

## Qualification before PCB/enclosure freeze

Obtain current revision-specific timing and electrical documents, sample price,
minimum quantity, stock/lead time, and lifecycle confirmation. Then test:

1. Native 60 Hz operation with a unique frame counter; check dropped/repeated frames.
2. Scrolling pixel art, small text and high-contrast moving sprites at 60 fps.
3. Legacy scaling and representative Lynx palette ramps, without cropping/stretching.
4. Backlight dimming, indoor/dark play, sunlight readability and off-axis viewing.
5. Total LCD/backlight/driver power and rotation/scanout memory bandwidth.

No vendor has been contacted and no sample ordered. The exact part cannot yet be
called settled; this research establishes the shortlist and the acceptance work.

## Sources

- [Playdate specifications](https://sdk.play.date/3.1.1/)
- [Sharp mobile panel catalog](https://global.sharp/products/device/lineup/selection/lcd/mobile/index.html)
- [Avnet's LS035Q7DD01 specifications](https://my.avnet.com/silica/products/new-products/npi/2026/avnet-displays-sharp-memory-lcd/)
- [All Shore product](https://www.allshore.com/Product/sunlight-viewable-tft-tft-sunlight-all-shore/asi-t-3501ra1en-a) and [datasheet](https://www.allshore.com/portals/0/PDFs/ASIT3501RA1ENA.PDF)
- [Densitron product](https://www.densitron.com/displays-computers/DMT035QVNXNT0-1C) and [datasheet](https://www.densitron.com/files/library/files/products/DMT035QVNXNT0-1C/Product%20Spec_DMT035QVNXNT0-1C_v0.1.pdf)
- [Leadtek product](https://www.leadtekdisplay.com/35-inch-tft-lcd-display-p-3132.html)
- [Toppan Blanview explanation](https://www.toppan.com/en/electronics/ortustech/technology/blanview/)
- [Toppan COM35H3R12ULC datasheet](https://www.fortec.uk/media/5a/eb/1e/1723463940/com35h3r12ulc_datasheet.pdf)
- [Toppan manufacturer discontinuation notice](https://www.fortec-integrated.de/fileadmin/pdf/produkte/EOL_PCN/TOPPAN_EOL_ORTUSTECH_business_discontinuation_2026-04.pdf)
- [Focus old panel](https://focuslcds.com/product/e35rb-fw115-n/) and [replacement](https://focuslcds.com/product/E35RB-B-RW600-N/)
- [Replacement PDF](https://focuslcds.com/wp-content/uploads/2025/09/E35RB-B-RW600-N_Spec.pdf)
- [Maclight module](https://www.szmaclight.com/product/3-5-inch-transflective-tft-lcd-module-240x320.html)
- [Phoenix module](https://www.phoenixdisplay.com/product/color-displays/3-5/pdi350mtqi-02/)
- [EastRising IPS fallback](https://www.buydisplay.com/ips-3-5-inch-full-viewing-640x480-tft-display-capacitive-touch-screen)
