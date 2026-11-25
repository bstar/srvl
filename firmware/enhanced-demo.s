; Original enhanced-console skeleton demo: the CPU programs the palette, the
; tile patterns and two tile maps, uploads one sprite, then each frame clears
; the back surface, draws four scaled sprites into it, scrolls both planes and
; hands the frame to scanout. Nothing is rendered by a host.
; Assemble with -D BAD_OWNER=1 for the negative ownership test, which draws
; into the displayed surface from the fourth frame on.
.setcpu "65C02"
.include "graphics-abi.inc"           ; generated from hardware/enhanced/graphics-abi.json
SHADOW=GFX_DESCRIPTOR
DIAGNOSTIC=$403f
FAILED=$e0
SPRITE_SOURCE=$004000
.segment "ZEROPAGE"
pointer: .res 2
frame: .res 1
sprite: .res 1
back_bank: .res 1
enabled: .res 1
scratch: .res 1

.segment "CODE"
reset:
    sei
    cld
    ldx #$ff
    txs
    stz frame
    stz enabled
    lda #$10
    sta DIAGNOSTIC
    stz VID_CONTROL
    stz VID_PALETTE_INDEX
    ldy #0
load_palette:                         ; entry = base[index & 15] ^ ($111 * bank)
    tya
    and #15
    asl
    tax
    tya
    lsr
    lsr
    lsr
    lsr
    sta scratch
    tya
    and #$f0
    ora scratch
    eor palette,x
    sta VID_PALETTE_LOW
    lda scratch
    eor palette+1,x
    sta VID_PALETTE_HIGH              ; commits the entry and advances the index
    iny
    bne load_palette
    stz VID_TILE_ADDRESS_LOW          ; patterns start at word 0
    stz VID_TILE_ADDRESS_HIGH
    ldx #0
load_patterns:
    txa
    and #3
    tay
    lda tile_patterns,x
    sta VID_TILE_DATA0,y              ; the fourth byte stores the row
    inx
    cpx #128
    bne load_patterns
    ; Both maps are contiguous: entries 0..2047 are the back plane, the rest
    ; the front plane. pointer counts entries.
    stz VID_TILE_ADDRESS_LOW
    lda #>VID_TILE_MAP0
    sta VID_TILE_ADDRESS_HIGH
    stz pointer
    stz pointer+1
load_maps:
    lda pointer+1
    cmp #8
    bcs front_entry
    lda pointer                       ; back plane: tiles 0..3 repeating
    and #3
    bra store_entry
front_entry:
    lda pointer                       ; front plane: mostly empty
    and #7
    tax
    lda front_tiles,x
store_entry:
    sta VID_TILE_DATA0
    lda pointer                       ; flips from column bits 4 and 5
    lsr
    lsr
    and #$0c
    sta scratch
    lda pointer+1                     ; palette bank changes every four rows
    asl
    asl
    asl
    asl
    ora scratch
    sta VID_TILE_DATA1                ; stores the entry
    inc pointer
    bne load_maps
    inc pointer+1
    lda pointer+1
    cmp #$10
    bne load_maps
    lda #3
    sta VID_PLANE_ENABLE
    ldx #GFX_DESCRIPTOR_BYTES-1
clear_shadow:
    stz SHADOW,x
    dex
    bpl clear_shadow
    lda #GFX_OP_WRITE_BYTE
    sta SHADOW+GFX_FIELD_FLAGS
    lda #>SPRITE_SOURCE
    sta SHADOW+GFX_FIELD_DESTINATION+1
    ldx #0
upload:
    stx SHADOW+GFX_FIELD_DESTINATION
    stx SHADOW+GFX_FIELD_TAG
    lda sprite_pixels,x
    sta SHADOW+GFX_FIELD_BYTE_VALUE
    jsr submit
    inx
    cpx #64
    bne upload
    lda #$20
    sta DIAGNOSTIC

next_frame:
    ; The surface that scanout does not own is the only one we may draw into.
    lda VID_STATUS
    and #VID_STATUS_FRONT
.ifdef BAD_OWNER
    ldx frame
    cpx #3
    bcc :+
    eor #VID_STATUS_FRONT
:
    cmp #0
.endif
    beq front_is_zero
    lda #^VID_SURFACE0
    bra have_back
front_is_zero:
    lda #^VID_SURFACE1
have_back:
    sta back_bank
    lda #<clear_template
    ldx #>clear_template
    jsr stage
    jsr submit
    stz sprite
next_sprite:
    lda #<sprite_template
    ldx #>sprite_template
    jsr stage
    ldx sprite
    txa
    asl
    asl
    asl
    asl
    asl
    asl
    sta SHADOW+GFX_FIELD_COLORS       ; band = 4*sprite: two below the front plane, two above
    stx SHADOW+GFX_FIELD_TAG
    lda frame                         ; x = 3*frame + offset, modulo 256
    asl
    clc
    adc frame
    clc
    adc sprite_x,x
    sta SHADOW+GFX_FIELD_X
    lda sprite_y,x
    sta SHADOW+GFX_FIELD_Y
    txa                               ; size = 16 + 2*((frame + 4*sprite) & 15)
    asl
    asl
    clc
    adc frame
    and #15
    asl
    clc
    adc #16
    sta SHADOW+GFX_FIELD_WIDTH
    sta SHADOW+GFX_FIELD_HEIGHT
    jsr submit
    inc sprite
    lda sprite
    cmp #4
    bne next_sprite
    ; Every command above has completed, so the back surface is whole.
    ; Plane scroll for this frame is committed by the same request as the swap.
    lda frame
    sta VID_PLANE0_X_LOW
    stz VID_PLANE0_X_HIGH
    sta VID_PLANE0_Y
    asl
    clc
    adc frame
    sta VID_PLANE1_X_LOW
    lda #1
    sta VID_PLANE1_X_HIGH
    lda #0
    sec
    sbc frame
    sta VID_PLANE1_Y
    ; The first swap happens with the display still disabled.
    lda enabled
    ora #(VID_CONTROL_SWAP | VID_CONTROL_LATCH_PLANES)
    sta VID_CONTROL
wait_swap:
    lda VID_STATUS
    and #VID_STATUS_SWAP_PENDING
    bne wait_swap
    lda #VID_CONTROL_ENABLE
    sta VID_CONTROL
    sta enabled
    lda VID_STATUS
    and #(VID_STATUS_UNDERRUN | VID_STATUS_OWNERSHIP_FAULT)
    bne fail
    inc frame
    lda frame
    and #$7f
    sta DIAGNOSTIC
    jmp next_frame

; A/X = template address. Copies it and fills in the frame-specific fields.
stage:
    sta pointer
    stx pointer+1
    ldy #GFX_DESCRIPTOR_BYTES-1
:
    lda (pointer),y
    sta SHADOW,y
    dey
    bpl :-
    lda back_bank
    sta SHADOW+GFX_FIELD_DESTINATION+2
    lda frame
    sta SHADOW+GFX_FIELD_TAG+1
    rts
submit:
    lda #GFX_CONTROL_SUBMIT
    sta GFX_CONTROL
:
    lda GFX_STATUS
    and #GFX_STATUS_DONE
    beq :-
    lda GFX_ERROR
    bne fail
    lda #GFX_CONTROL_ACKNOWLEDGE
    sta GFX_CONTROL
    rts
fail:
    sei
    lda #FAILED
    sta DIAGNOSTIC
:
    bra :-

.segment "RODATA"
; flags, fill index, palette/band, tag, source24, destination24, source W/H,
; source/destination strides, X/Y, destination W/H, clip bounds, byte data.
.macro descriptor flags, color, source, sw, sh, ss, w, h
    .byte flags,color,0
    .word 0
    .faraddr source,0
    .word sw,sh,ss,640,0,0,w,h,0,0,320,204
    .byte 0
.endmacro
clear_template:  descriptor $01,0,0,1,1,1,320,204     ; uncovered, so the planes show through
sprite_template: descriptor $40,0,SPRITE_SOURCE,8,8,8,16,16
sprite_x: .byte 0,61,122,183
sprite_y: .byte 8,54,100,146
palette:                              ; low byte G,B then high nibble R
    .word $000,$113,$f00,$0f0,$00f,$ff0,$f0f,$0ff
    .word $fff,$f80,$8f0,$08f,$f08,$80f,$888,$444
tile_patterns:                        ; four 8x8 tiles; each byte is two pixels, left one in the low nibble
    .byte $00,$00,$00,$00
    .byte $00,$00,$00,$00
    .byte $00,$00,$00,$00
    .byte $00,$00,$00,$00
    .byte $00,$00,$00,$00
    .byte $00,$00,$00,$00
    .byte $00,$00,$00,$00
    .byte $00,$00,$00,$00
    .byte $11,$11,$11,$01
    .byte $21,$22,$22,$00
    .byte $21,$33,$03,$00
    .byte $21,$43,$00,$00
    .byte $21,$03,$00,$00
    .byte $21,$00,$00,$00
    .byte $01,$00,$00,$00
    .byte $00,$00,$00,$00
    .byte $65,$87,$a9,$cb
    .byte $87,$a9,$cb,$65
    .byte $a9,$cb,$65,$87
    .byte $cb,$65,$87,$a9
    .byte $65,$87,$a9,$cb
    .byte $87,$a9,$cb,$65
    .byte $a9,$cb,$65,$87
    .byte $cb,$65,$87,$a9
    .byte $ff,$ff,$ff,$ff
    .byte $0f,$00,$00,$e0
    .byte $0f,$00,$00,$e0
    .byte $0f,$09,$00,$e0
    .byte $0f,$00,$00,$e0
    .byte $0f,$00,$00,$e0
    .byte $0f,$00,$00,$e0
    .byte $ef,$ee,$ee,$ee
front_tiles: .byte 3,0,0,0,0,1,0,0
sprite_pixels:
    .byte 0,0,2,2,2,2,0,0
    .byte 0,2,3,3,3,3,2,0
    .byte 2,3,4,5,5,4,3,2
    .byte 2,3,5,8,9,5,3,2
    .byte 2,3,5,10,11,5,3,2
    .byte 2,3,4,5,5,4,3,2
    .byte 0,2,6,7,12,13,2,0
    .byte 0,0,14,15,15,14,0,0
.segment "VECTORS"
    .word fail,reset,fail
