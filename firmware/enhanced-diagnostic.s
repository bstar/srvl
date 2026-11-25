; Original CPU-executed enhanced graphics diagnostic; no host rendering.
.setcpu "65C02"
.macpack longbranch
.include "graphics-abi.inc"           ; generated from hardware/enhanced/graphics-abi.json
STATUS=GFX_STATUS
CONTROL=GFX_CONTROL
ENABLE_IRQ=GFX_IRQ_ENABLE
ERROR=GFX_ERROR
TAG=GFX_TAG
DATA=GFX_DATA
SHADOW=GFX_DESCRIPTOR
DIAGNOSTIC=$403f
.segment "ZEROPAGE"
pointer: .res 2
expected_tag: .res 2
expected_error: .res 1
upload_value: .res 1
command_index: .res 1
irq_count: .res 1

.segment "CODE"
reset:
    sei
    cld
    ldx #$ff
    txs
    stz irq_count
    stz expected_error
    lda #$10
    sta DIAGNOSTIC
    ; All 36 shadow bytes are software-initialized, including unused fields.
    ldx #35
clear_shadow:
    stz SHADOW,x
    dex
    bpl clear_shadow
    lda #2                       ; WRITE_BYTE
    sta SHADOW
    lda #$40
    sta SHADOW+9
    lda #$10
    sta SHADOW+4
    sta expected_tag+1
    stz upload_value
    ldx #0
upload:
    txa
    sta SHADOW+3
    sta expected_tag
    clc
    adc #3
    sta SHADOW+8
    lda upload_value
    sta SHADOW+35
    lda #1
    sta CONTROL
    jsr wait_result
    lda upload_value
    clc
    adc #17
    sta upload_value
    inx
    cpx #96
    bne upload
    ; Probe unaligned first/second/last source bytes through READ_BYTE.
    lda #3
    sta SHADOW
    ldx #0
read_probe:
    lda probe_offsets,x
    sta SHADOW+8
    txa
    sta SHADOW+3
    sta expected_tag
    lda #1
    sta CONTROL
    jsr wait_result
    lda DATA
    cmp probe_values,x
    jne fail
    inx
    cpx #3
    bne read_probe
    lda #$20
    sta DIAGNOSTIC
    lda #<descriptors
    sta pointer
    lda #>descriptors
    sta pointer+1
    stz command_index
next_descriptor:
    jsr stage_descriptor
    ldx command_index
    lda expected_errors,x
    sta expected_error
    lda #1
    sta CONTROL
    cpx #0
    bne normal_wait
    ; The first full clear is still in flight. A shadow edit and duplicate GO
    ; must not replace its accepted tag or descriptor.
    lda #$ee
    sta SHADOW+3
    lda #5                       ; clear-reject + GO: new rejection wins
    sta CONTROL
    lda STATUS
    and #$10
    jeq fail
    lda #4
    sta CONTROL
normal_wait:
    jsr wait_result
    clc
    lda pointer
    adc #36
    sta pointer
    bcc :+
    inc pointer+1
:
    inc command_index
    lda command_index
    cmp #9
    bne next_descriptor
    ; The tenth descriptor completes via a real CPU IRQ. Its handler checks
    ; the held result, acknowledges it and must execute exactly once.
    jsr stage_descriptor
    stz expected_error
    lda #$30
    sta DIAGNOSTIC
    lda #1
    sta ENABLE_IRQ
    cli
    sta CONTROL
wait_irq:
    lda irq_count
    beq wait_irq
    sei
    cmp #1
    jne fail
    lda #$a5
    sta DIAGNOSTIC
success:
    bra success

stage_descriptor:
    ldy #0
:
    lda (pointer),y
    sta SHADOW,y
    iny
    cpy #36
    bne :-
    lda SHADOW+3
    sta expected_tag
    lda SHADOW+4
    sta expected_tag+1
    rts
wait_result:
    lda STATUS
    and #4
    beq wait_result
    jsr check_result
    lda #2
    sta CONTROL
    rts
check_result:
    lda ERROR
    cmp expected_error
    bne fail
    lda TAG
    cmp expected_tag
    bne fail
    lda TAG+1
    cmp expected_tag+1
    bne fail
    rts
irq:
    pha
    phx
    phy
    jsr check_result
    inc irq_count
    lda #2
    sta CONTROL
    ply
    plx
    pla
    rti
fail:
    sei
    lda #$e0
    sta DIAGNOSTIC
:
    bra :-

.segment "RODATA"
probe_offsets: .byte 3,4,98
probe_values: .byte 0,17,79
expected_errors: .byte 0,0,0,0,0,1,2,4,5
; flags, fill index, bank/band, tag, source24, dest24, source W/H,
; source/dest strides, signed12 X/Y, destination W/H, clip bounds, byte data.
.macro descriptor flags, color, bank, tag, source, sw, sh, ss, ds, xpos, ypos, w, h
    .byte flags,color,bank
    .word tag
    .faraddr source,$180000
    .word sw,sh,ss,ds,(xpos & $fff),(ypos & $fff),w,h,0,0,320,204
    .byte 0
.endmacro
descriptors:
    descriptor $01,0,0,$2001,$4003,8,8,11,640,0,0,320,204
    descriptor $70,0,$30,$2002,$4003,8,8,11,640,-3,-2,37,23
    descriptor $68,0,$7b,$2003,$4003,5,7,5,640,298,191,19,11
    descriptor $00,0,$40,$2004,$4003,1,1,1,640,48,17,7,5
    descriptor $05,0,$60,$2005,$4003,8,8,11,640,319,203,3,3
    descriptor $40,0,0,$2006,$4003,8,8,11,640,0,0,0,16
    descriptor $40,0,0,$2007,$4003,8,8,11,641,0,0,16,16
    descriptor $40,0,0,$2008,$180000,8,8,11,640,0,0,16,16
    descriptor $80,0,0,$2009,$4003,8,8,11,640,0,0,16,16
    descriptor $05,$27,$80,$2ff0,$4003,8,8,11,640,120,80,16,16
.segment "VECTORS"
    .word fail,reset,irq
