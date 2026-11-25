; Original enhanced-console skeleton demo: the CPU programs the palette,
; uploads one sprite, then each frame clears the back surface, draws four
; scaled sprites into it and hands it to scanout. Nothing is rendered by a host.
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
    ldx #0
load_palette:
    lda palette,x
    sta VID_PALETTE_LOW
    inx
    lda palette,x
    sta VID_PALETTE_HIGH              ; commits the entry and advances the index
    inx
    cpx #32
    bne load_palette
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
    sta SHADOW+GFX_FIELD_COLORS       ; band = sprite number, palette row 0
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
    ; The first swap happens with the display still disabled.
    lda enabled
    ora #VID_CONTROL_SWAP
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
clear_template:  descriptor $05,1,0,1,1,1,320,204
sprite_template: descriptor $40,0,SPRITE_SOURCE,8,8,8,16,16
sprite_x: .byte 0,61,122,183
sprite_y: .byte 8,54,100,146
palette:                              ; low byte G,B then high nibble R
    .word $000,$113,$f00,$0f0,$00f,$ff0,$f0f,$0ff
    .word $fff,$f80,$8f0,$08f,$f08,$80f,$888,$444
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
