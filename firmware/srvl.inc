; SPDX-License-Identifier: GPL-2.0-or-later
; Prototype map, not the Lynx memory map. See docs/architecture/software-prototype.md.
TILES       = $2000
ATTRS       = $2800
PALETTE     = $4000
VIDEO       = $4020
IRQ_ENABLE  = $4023
IRQ_PENDING = $4024
FRAME_LO    = $4025
FRAME_HI    = $4026
CPU_SLEEP   = $4027
BUTTONS     = $4030
DIAGNOSTIC  = $403f
LEVEL_TIMER = $4040 ; control: bit0 run, bit1 reset; +1 low, +2/+3 latched high
TOTAL_TIMER = $4044
SPRITES     = $4100
TONE_L      = $4300
TONE_R      = $4308

RIGHT = $01
LEFT  = $02
DOWN  = $04
UP    = $08
BTN_A = $10
BTN_B = $20
START = $40
