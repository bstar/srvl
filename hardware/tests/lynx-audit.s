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
    ; Fill the Lynx's packed 4bpp framebuffer at $4000 with palette index 1.
    lda #0
    sta $00
    lda #$40
    sta $01
    ldx #32
    ldy #0
    lda #$11
fill:
    sta ($00),y
    iny
    bne fill
    inc $01
    dex
    bne fill
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
    lda #$0f
    sta $fda1
    stz $fdb1
    bra poll_buttons
pressed:
    stz $fda1
    lda #$0f
    sta $fdb1
    bra poll_buttons
