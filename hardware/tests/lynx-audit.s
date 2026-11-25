; Original diagnostic for the upstream Lynx core's BS93 RAM loader.
; No Atari boot ROM or commercial software is used.
.setcpu "65C02"
.org $0200
start:
    sei
    cld
    ldx #$ff
    txs
    ; Exercise RAM with a read/modify/check operation.
    lda #$5a
    sta $1000
    inc $1000
    lda $1000
    cmp #$5b
    bne fail
    ; Suzy unsigned multiplication: $1234 * 3 = $0000369c.
    stz $fc92
    lda #3
    sta $fc52
    stz $fc53
    lda #$34
    sta $fc54
    lda #$12
    sta $fc55
    ldx #$ff
wait_math:
    dex
    bne wait_math
    lda $fc60
    cmp #$9c
    bne fail
    lda $fc61
    cmp #$36
    bne fail
    lda $fc62
    ora $fc63
    bne fail
    bra begin_frame
fail:
    ; A failed arithmetic/RAM check never starts display DMA.
    bra fail
begin_frame:
.ifdef TANG_CHECK_CART
    ; The BS93 bank mask is zero, so each forced read must return image byte 0.
    ; Toggle cartridge strobe to force a fetch, then exercise the shared-word
    ; cache repeatedly. A missing/incorrect SDRAM response prevents display.
    ldy #3
cart_probe:
    lda #1
    sta $fd87
    stz $fd87
    ldx #255
cart_wait:
    dex
    bne cart_wait
    lda $fcb2
    cmp #$80
    bne fail
    dey
    bne cart_probe
.endif
.ifdef TANG_CHECK_AUDIO
    ; Route channel 0 to left, channel 1 to right. Independent timers drive
    ; alternating-feedback square waves; this uses actual Mikey audio logic.
    lda #$ed
    sta $fd50
    stz $fd25
    stz $fd2d
    lda #1
    sta $fd21
    sta $fd29
    stz $fd23
    stz $fd2b
    lda #249
    sta $fd24
    sta $fd26
    lda #199
    sta $fd2c
    sta $fd2e
    lda #32
    sta $fd20
    lda #16
    sta $fd28
    lda #$18
    sta $fd25
    sta $fd2d
.endif
    ; Fill the Lynx's packed 4bpp framebuffer at $4000 with palette index 1.
    lda #0
    sta $00
    lda #$40
    sta $01
    ldx #32
    ldy #0
    lda #$11
fill:
.ifdef TANG_CHECK_VIDEO
    ; Vary both nibbles across rows/columns for the real-core scanout test.
    tya
.endif
    sta ($00),y
    iny
    bne fill
    inc $01
    dex
    bne fill
.ifdef TANG_CHECK_VIDEO
    ; All indexes have distinct RGB444 shades. Index 1 remains the live
    ; green/red button result, so capture must preserve palette timing too.
    ldx #15
init_palette:
    txa
    sta $02
    sta $fda0,x
    asl
    asl
    asl
    asl
    ora $02
    sta $fdb0,x
    dex
    bpl init_palette
.endif
    stz $fd94
    lda #$40
    sta $fd95
    lda #$0d
    sta $fd92
    ; Timer 0 drives lines; timer 2 counts linked lines.
    lda #158
    sta $fd00
    sta $fd02
    lda #104
    sta $fd08
    sta $fd0a
    lda #$1f
    sta $fd09
    lda #$18
    sta $fd01
poll_buttons:
    ; Green when idle, red when A is held. This is the test's result channel.
    lda $fcb0
    and #1
    bne pressed
.ifdef TANG_CHECK_AUDIO
    lda #32
    sta $fd20
    lda #16
    sta $fd28
.endif
    lda #$0f
    sta $fda1
    stz $fdb1
    bra poll_buttons
pressed:
.ifdef TANG_CHECK_AUDIO
    lda #16
    sta $fd20
    lda #8
    sta $fd28
.endif
    stz $fda1
    lda #$0f
    sta $fdb1
    bra poll_buttons
