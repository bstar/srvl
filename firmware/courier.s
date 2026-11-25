; SPDX-License-Identifier: GPL-2.0-or-later
; CIRCUIT COURIER: original 65C02 game. All game rules execute on the HDL CPU.
.setcpu "65C02"
.include "srvl.inc"

.segment "ZEROPAGE"
tile_ptr:      .res 2
attr_ptr:      .res 2
text_ptr:      .res 2
text_color:    .res 1
ticks:         .res 1
last_tick:     .res 1
joy:           .res 1
previous_joy:  .res 1
pressed:       .res 1
state:         .res 1 ; 0 title, 1 playing, 2 delivered, 3 link lost
score:         .res 1
level:         .res 1 ; four circuits; total active time is the campaign score
dock_x:        .res 1
dock_y:        .res 1
time_work:     .res 3
time_digit:    .res 1
hud_offset:    .res 1
player_x:      .res 1 ; logical playfield coordinates, displayed at +32,+56
player_y:      .res 1
packet_x:      .res 1
packet_y:      .res 1
enemy_x:       .res 5
enemy_y:       .res 5
enemy_nodes:   .res 5
enemy_nexts:   .res 5
enemy_dirs:    .res 5
enemy_progress:.res 5
enemy_count:   .res 1
player_node:   .res 1
player_next:   .res 1
player_dir:    .res 1
player_progress:.res 1
requested_dir: .res 1
jam_timer:     .res 1
jam_cooldown:  .res 1
actor_id:      .res 1
actor_node:    .res 1
actor_next:    .res 1
actor_dir:     .res 1
actor_progress:.res 1
position_x:    .res 1
position_y:    .res 1
mask:          .res 1
candidate_dir: .res 1
candidate_node:.res 1
direction_index:.res 1
best_distance: .res 1
best_dir:      .res 1
target_node:   .res 1
maze_ptr:      .res 2
dist_ptr:      .res 2
distance_ptr:  .res 2
distance_source:.res 1
distance_dest: .res 1
source_ptr:    .res 2
object_index:  .res 1
scan_index:    .res 1
row_count:     .res 1
near_limit:    .res 1
speed:         .res 1
target_x:      .res 1
target_y:      .res 1
sound_timer:   .res 1
rng:           .res 2
slots:         .res 32
layout_nodes:  .res 5
layout_x:      .res 5 ; spawn, three cards in order, dock
layout_y:      .res 5
random_base:   .res 1
route_length:  .res 2
route_dx:      .res 1
deadline:      .res 2 ; route-dependent qualifying time in milliseconds

.segment "CODE"
.export reset, irq_handler, nmi_handler
.proc reset
    sei
    cld
    ldx #$ff
    txs
    lda #0
    tax
@clear_zp:
    sta $00,x
    inx
    bne @clear_zp
    ; CPU-executed bus checks: RAM, ROM write protection, unmapped reads.
    lda #$5a
    sta $1fff
    cmp $1fff
    bne @bus_fault
    lda #0
    sta $8000
    lda $8000
    cmp #$78                 ; reset begins with SEI
    bne @bus_fault
    lda #$ff
    sta $6000
    lda $6000
    beq @bus_ok
@bus_fault:
    lda #$ee
    sta DIAGNOSTIC
    bra @bus_fault
@bus_ok:
    lda #$e1
    sta rng
    lda #$ac
    sta rng+1
    ldx #0
@palette:
    lda colors,x
    sta PALETTE,x
    inx
    cpx #32
    bne @palette
    ; Initialize both complete 2 KiB VRAM banks before enabling video.
    lda #<TILES
    sta tile_ptr
    lda #>TILES
    sta tile_ptr+1
    lda #1
    jsr fill_bank
    lda #>ATTRS
    sta tile_ptr+1
    lda #$a0
    jsr fill_bank
    jsr draw_border
    lda #$f0
    sta text_color
    lda #<(TILES+40+12)
    sta tile_ptr
    lda #>(TILES+40+12)
    sta tile_ptr+1
    lda #<title
    sta text_ptr
    lda #>title
    sta text_ptr+1
    jsr print
    lda #$c0
    sta text_color
    lda #<(TILES+80+6)
    sta tile_ptr
    lda #>(TILES+80+6)
    sta tile_ptr+1
    lda #<subtitle
    sta text_ptr
    lda #>subtitle
    sta text_ptr+1
    jsr print
    lda #<(TILES+24*40+4)
    sta tile_ptr
    lda #>(TILES+24*40+4)
    sta tile_ptr+1
    lda #<instructions
    sta text_ptr
    lda #>instructions
    sta text_ptr+1
    jsr print
    lda #$50
    sta text_color
    lda #<(TILES+4*40+4)
    sta tile_ptr
    lda #>(TILES+4*40+4)
    sta tile_ptr+1
    lda #<score_label
    sta text_ptr
    lda #>score_label
    sta text_ptr+1
    jsr print
    lda #<(TILES+4*40+25)
    sta tile_ptr
    lda #>(TILES+4*40+25)
    sta tile_ptr+1
    lda #<level_label
    sta text_ptr
    lda #>level_label
    sta text_ptr+1
    jsr print
    lda #<(TILES+5*40+3)
    sta tile_ptr
    lda #>(TILES+5*40+3)
    sta tile_ptr+1
    lda #<time_label
    sta text_ptr
    lda #>time_label
    sta text_ptr+1
    jsr print
    jsr reset_world
    stz state
    lda #<prompt
    sta text_ptr
    lda #>prompt
    sta text_ptr+1
    jsr message
    jsr update_sprites
    jsr report_state
    lda #1
    sta VIDEO
    sta IRQ_PENDING
    sta IRQ_ENABLE
    cli
@wait:
    sei
    lda ticks
    cmp last_tick
    bne @update
    lda #1
    sta CPU_SLEEP
    cli
    bra @wait
@update:
    sta last_tick
    cli
    jsr frame_update
    jmp @wait
.endproc

.proc fill_bank
    ldx #8
    ldy #0
@byte:
    sta (tile_ptr),y
    iny
    bne @byte
    inc tile_ptr+1
    dex
    bne @byte
    rts
.endproc

.proc draw_border
    ldx #3
@horizontal:
    lda #2
    sta TILES+6*40,x
    sta TILES+23*40,x
    lda #$30
    sta ATTRS+6*40,x
    sta ATTRS+23*40,x
    inx
    cpx #37
    bne @horizontal
    lda #<(TILES+7*40)
    sta tile_ptr
    lda #>(TILES+7*40)
    sta tile_ptr+1
    ldx #16
@vertical:
    jsr attribute_pointer
    lda #2
    ldy #3
    sta (tile_ptr),y
    ldy #36
    sta (tile_ptr),y
    lda #$30
    sta (attr_ptr),y
    ldy #3
    sta (attr_ptr),y
    clc
    lda tile_ptr
    adc #40
    sta tile_ptr
    bcc @next
    inc tile_ptr+1
@next:
    dex
    bne @vertical
    rts
.endproc

.proc attribute_pointer
    lda tile_ptr
    sta attr_ptr
    clc
    lda tile_ptr+1
    adc #8
    sta attr_ptr+1
    rts
.endproc

.proc print
    jsr attribute_pointer
    ldy #0
@char:
    lda (text_ptr),y
    beq @done
    sta (tile_ptr),y
    lda text_color
    sta (attr_ptr),y
    iny
    bne @char
@done:
    rts
.endproc

.proc message
    lda state
    beq @center
    ; Outcome messages stay in the HUD, outside every sprite's playfield.
    lda #<(TILES+3*40+9)
    sta tile_ptr
    lda #>(TILES+3*40+9)
    sta tile_ptr+1
    bra @print
@center:
    lda #<(TILES+14*40+9)
    sta tile_ptr
    lda #>(TILES+14*40+9)
    sta tile_ptr+1
@print:
    lda #$f0
    sta text_color
    jmp print
.endproc

.proc clear_message
    lda #<(TILES+14*40+9)
    sta tile_ptr
    lda #>(TILES+14*40+9)
    sta tile_ptr+1
    jsr clear_message_line
    lda #<(TILES+3*40+9)
    sta tile_ptr
    lda #>(TILES+3*40+9)
    sta tile_ptr+1
    jmp clear_message_line
.endproc

.proc clear_message_line
    jsr attribute_pointer
    ldy #23
@clear:
    lda #1
    sta (tile_ptr),y
    lda #$a0
    sta (attr_ptr),y
    dey
    bpl @clear
    rts
.endproc

.proc reset_world
    jsr random_layout
    lda layout_nodes
    sta player_node
    sta player_next
    lda layout_x
    sta player_x
    lda layout_y
    sta player_y
    lda layout_x+4
    sta dock_x
    lda layout_y+4
    sta dock_y
    stz player_dir
    stz requested_dir
    stz player_progress
    stz jam_timer
    stz jam_cooldown
    stz score
    stz sound_timer
    stz TONE_L+3
    stz TONE_R+3
    jsr next_packet
    lda #'0'
    sta TILES+4*40+12
    ldx #63
    lda #0
@clear:
    sta SPRITES,x
    dex
    bpl @clear
    lda #4
    sta SPRITES+4
    lda #5
    sta SPRITES+12
    lda #13
    sta SPRITES+60
    lda #1
    sta SPRITES+5
    sta SPRITES+13
    sta SPRITES+61
    ldx #0
@guard:
    lda enemy_colors,x
    ldy enemy_sprite_offsets,x
    sta SPRITES+4,y
    lda #1
    sta SPRITES+5,y
    inx
    cpx enemy_count
    bne @guard
    jsr clear_message
    jsr draw_maze
    ldx level
    txa
    clc
    adc #'1'
    sta TILES+4*40+31
    lda level_colors_lo,x
    sta PALETTE+6
    lda level_colors_hi,x
    sta PALETTE+7
    lda level_names_lo,x
    sta text_ptr
    lda level_names_hi,x
    sta text_ptr+1
    lda #<(TILES+2*40+6)
    sta tile_ptr
    lda #>(TILES+2*40+6)
    sta tile_ptr+1
    lda #$c0
    sta text_color
    jsr print
    lda #<(TILES+3)
    sta tile_ptr
    lda #>(TILES+3)
    sta tile_ptr+1
    lda #<guards_label
    sta text_ptr
    lda #>guards_label
    sta text_ptr+1
    jsr print
    lda enemy_count
    ora #'0'
    sta TILES+10
    jsr draw_jam_state
    jsr draw_limit
    jsr draw_times
    rts
.endproc

.proc next_packet
    ; Each packet is a junction on the connected maze.
    ldx score
    lda layout_x+1,x
    sta packet_x
    lda layout_y+1,x
    sta packet_y
    rts
.endproc

.proc frame_update
    jsr advance_sound
    lda BUTTONS
    sta joy
    lda previous_joy
    eor #$ff
    and joy
    sta pressed
    lda joy
    sta previous_joy
    lda state
    cmp #1
    bne @menu
    jsr game_step
    ; Counters keep full millisecond precision. Refresh the live digits at
    ; 30 Hz to leave more CPU time for gameplay; always draw the frozen result.
    lda state
    cmp #1
    bne @time
    lda ticks
    and #1
    bne @draw
@time:
    jsr draw_times
    jmp @draw
@menu:
    lda pressed
    and #(BTN_A|START)
    beq @draw
    lda state
    cmp #3
    beq @begin              ; Retry this circuit; failed time stays in total.
    cmp #2
    bne @new_run
    lda level
    cmp #3
    beq @new_run
    inc level
    bra @begin
@new_run:
    stz level
    ; Human start timing perturbs the reproducible 16-bit PRNG sequence.
    lda FRAME_LO
    eor rng
    sta rng
    lda FRAME_HI
    eor rng+1
    ora #1                 ; Never permit the all-zero LFSR state.
    sta rng+1
    lda #2
    sta TOTAL_TIMER
@begin:
    jsr reset_world
    lda #1
    sta TOTAL_TIMER
    lda #3
    sta LEVEL_TIMER
    lda #1
    sta state
    jsr draw_times
@draw:
    jsr update_sprites
    jsr report_state
    rts
.endproc

.proc game_step
    jsr check_deadline
    bcc @play
    rts
@play:
    jsr jam_step
    jsr player_step
    jsr guards_step
    lda jam_timer
    bne @packet
    stz actor_id
@contact:
    ldx actor_id
    lda enemy_x,x
    sta target_x
    lda enemy_y,x
    sta target_y
    lda #10
    sta near_limit
    jsr within_target
    bcs @lost
    inc actor_id
    lda actor_id
    cmp enemy_count
    bne @contact
    bra @packet
@lost:
    lda #3
    sta state
    jsr stop_times
    lda #<lost_message
    sta text_ptr
    lda #>lost_message
    sta text_ptr+1
    jsr message
    ldx #4
    jsr play_sound
    rts
@packet:
    lda score
    cmp #3
    beq @dock
    lda packet_x
    sta target_x
    lda packet_y
    sta target_y
    jsr near_target
    bcc @done
    inc score
    lda score
    clc
    adc #'0'
    sta TILES+4*40+12
    ldx score
    dex
    jsr play_sound
    lda score
    cmp #3
    beq @unlock
    jsr next_packet
    rts
@unlock:
    stz SPRITES+13
    lda #4
    sta SPRITES+60
    rts
@dock:
    lda dock_x
    sta target_x
    lda dock_y
    sta target_y
    jsr near_target
    bcc @done
    jsr stop_times
    jsr check_deadline
    bcs @done
    lda #2
    sta state
    lda #<clear_message_text
    sta text_ptr
    lda #>clear_message_text
    sta text_ptr+1
    lda level
    cmp #3
    bne @delivered
    lda #<win_message
    sta text_ptr
    lda #>win_message
    sta text_ptr+1
@delivered:
    jsr message
    ldx #3
    jsr play_sound
@done:
    rts
.endproc

; Hold to move, release to stop. Buffered junction turns and immediate reverse.
.proc player_step
    lda joy
    and #15
    sta mask
    and #(RIGHT|LEFT)
    cmp #(RIGHT|LEFT)
    bne @vertical
    lda mask
    and #(DOWN|UP)
    sta mask
@vertical:
    lda mask
    and #(DOWN|UP)
    cmp #(DOWN|UP)
    bne @held
    lda mask
    and #(RIGHT|LEFT)
    sta mask
@held:
    lda mask
    bne @input
    ; Preserve edge position and heading so resuming cannot snap to a node.
    stz requested_dir
    rts
@input:
    lda pressed
    and mask
    bne @request
    lda requested_dir
    and mask
    bne @load
    lda mask
@request:
    sta mask
    and #(RIGHT|LEFT)
    cmp #RIGHT
    beq @right
    cmp #LEFT
    beq @left
    lda mask
    and #(DOWN|UP)
    cmp #DOWN
    beq @down
    cmp #UP
    bne @load
    lda #UP
    bra @store
@right:
    lda #RIGHT
    bra @store
@left:
    lda #LEFT
    bra @store
@down:
    lda #DOWN
@store:
    sta requested_dir
@load:
    lda player_node
    sta actor_node
    lda player_next
    sta actor_next
    lda player_dir
    sta actor_dir
    lda player_progress
    sta actor_progress
    beq @junction
    ldx actor_dir
    lda opposite_dir,x
    cmp requested_dir
    bne @advance
    lda actor_node
    pha
    lda actor_next
    sta actor_node
    pla
    sta actor_next
    lda #32
    sec
    sbc actor_progress
    sta actor_progress
    lda requested_dir
    sta actor_dir
    bra @advance
@junction:
    ldy actor_node
    lda (maze_ptr),y
    sta mask
    and requested_dir
    beq @straight
    lda requested_dir
    sta actor_dir
    bra @advance
@straight:
    lda mask
    and actor_dir
    bne @advance
    stz actor_dir
@advance:
    lda #2
    sta speed
    lda joy
    and #BTN_B
    beq @move
    dec speed
@move:
    jsr advance_actor
    lda actor_node
    sta player_node
    lda actor_next
    sta player_next
    lda actor_dir
    sta player_dir
    lda actor_progress
    sta player_progress
    jsr actor_position
    lda position_x
    sta player_x
    lda position_y
    sta player_y
    rts
.endproc

.proc advance_actor
    lda actor_dir
    beq @done
    lda actor_progress
    bne @move
    ldx actor_dir
    lda direction_delta,x
    clc
    adc actor_node
    sta actor_next
@move:
    clc
    lda actor_progress
    adc speed
    cmp #32
    bcc @store
    stz actor_progress
    lda actor_next
    sta actor_node
    rts
@store:
    sta actor_progress
@done:
    rts
.endproc

.proc actor_position
    ldy actor_node
    lda node_xs,y
    sta position_x
    lda node_ys,y
    sta position_y
    lda actor_dir
    cmp #RIGHT
    beq @right
    cmp #LEFT
    beq @left
    cmp #DOWN
    beq @down
    cmp #UP
    beq @up
    rts
@right:
    clc
    lda position_x
    adc actor_progress
    sta position_x
    rts
@left:
    sec
    lda position_x
    sbc actor_progress
    sta position_x
    rts
@down:
    clc
    lda position_y
    adc actor_progress
    sta position_y
    rts
@up:
    sec
    lda position_y
    sbc actor_progress
    sta position_y
    rts
.endproc

.proc guards_step
    lda jam_timer
    bne @done
    lda level
    bne @start
    lda ticks
    and #3
    beq @done              ; First circuit guards move on three of four frames.
@start:
    stz actor_id
@guard:
    ldx actor_id
    lda enemy_nodes,x
    sta actor_node
    lda enemy_nexts,x
    sta actor_next
    lda enemy_dirs,x
    sta actor_dir
    lda enemy_progress,x
    sta actor_progress
    bne @move
    jsr guard_choose
@move:
    lda #1
    sta speed
    jsr advance_actor
    ldx actor_id
    lda actor_node
    sta enemy_nodes,x
    lda actor_next
    sta enemy_nexts,x
    lda actor_dir
    sta enemy_dirs,x
    lda actor_progress
    sta enemy_progress,x
    jsr actor_position
    ldx actor_id
    lda position_x
    sta enemy_x,x
    lda position_y
    sta enemy_y,x
    inc actor_id
    lda actor_id
    cmp enemy_count
    bne @guard
@done:
    rts
.endproc

; Junction steering uses ROM shortest-path tables, not a host-side pathfinder.
.proc guard_choose
    lda player_node
    sta target_node
    lda actor_id
    cmp #1
    bne @warden
    lda player_next         ; Ambusher aims at the courier's next junction.
    sta target_node
    bra @legal
@warden:
    cmp #2
    bne @patrol
    lda player_node
    ldx actor_node
    jsr maze_distance
    cmp #4
    bcc @legal
    ldx score
    lda layout_nodes+1,x    ; Card warden; score 3 selects the dock.
    sta target_node
    bra @legal
@patrol:
    cmp #3
    bne @hunter
    lda ticks
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    tax
    lda patrol_nodes,x
    sta target_node
    bra @legal
@hunter:
    cmp #4
    bne @legal
    lda player_next
    sta target_node
@legal:
    ldy actor_node
    lda (maze_ptr),y
    sta mask
    ldx actor_dir
    lda opposite_dir,x
    eor #$ff
    and mask
    beq @dead_end
    sta mask              ; Avoid gratuitous reversals; dead ends may reverse.
@dead_end:
    lda #$ff
    sta best_distance
    stz best_dir
    stz direction_index
@choice:
    ldx direction_index
    lda direction_bits,x
    sta candidate_dir
    and mask
    beq @next
    ldx candidate_dir
    lda direction_delta,x
    clc
    adc actor_node
    tax
    lda target_node
    jsr maze_distance
    cmp best_distance
    bcs @next
    sta best_distance
    lda candidate_dir
    sta best_dir
@next:
    inc direction_index
    lda direction_index
    cmp #4
    bne @choice
    lda best_dir
    sta actor_dir
    rts
.endproc

.proc jam_step
    lda jam_cooldown
    beq @active
    dec jam_cooldown
    bne @active
    jsr draw_jam_state
@active:
    lda jam_timer
    beq @button
    dec jam_timer
    bne @button
    jsr draw_jam_state
@button:
    lda pressed
    and #BTN_A
    beq @done
    lda jam_cooldown
    bne @done
    lda #60
    sta jam_timer
    ldx level
    lda jam_cooldowns,x
    sta jam_cooldown
    jsr draw_jam_state
    ldx #2
    jsr play_sound
@done:
    rts
.endproc

.proc draw_jam_state
    lda #<jam_ready
    sta text_ptr
    lda #>jam_ready
    sta text_ptr+1
    lda jam_cooldown
    beq @active
    lda #<jam_wait
    sta text_ptr
    lda #>jam_wait
    sta text_ptr+1
@active:
    lda jam_timer
    beq @print
    lda #<jam_active
    sta text_ptr
    lda #>jam_active
    sta text_ptr+1
@print:
    lda #<(TILES+3*40+9)
    sta tile_ptr
    lda #>(TILES+3*40+9)
    sta tile_ptr+1
    lda #$c0
    sta text_color
    jmp print
.endproc

; Maximal-period 16-bit Galois LFSR. Eight steps mix each output byte.
.proc random_byte
    ldy #8
@step:
    lsr rng+1
    ror rng
    bcc @next
    lda rng+1
    eor #$b4
    sta rng+1
@next:
    dey
    bne @step
    lda rng
    eor rng+1
    rts
.endproc

.proc maze_distance
    sta distance_source
    stx distance_dest
    lsr
    lsr
    lsr
    sta distance_ptr+1
    lda distance_source
    asl
    asl
    asl
    asl
    asl
    clc
    adc dist_ptr
    sta distance_ptr
    lda distance_ptr+1
    adc dist_ptr+1
    sta distance_ptr+1
    ldy distance_dest
    lda (distance_ptr),y
    rts
.endproc

.proc random_layout
    ldx level
    lda maze_masks_lo,x
    sta maze_ptr
    lda maze_masks_hi,x
    sta maze_ptr+1
    lda maze_distances_lo,x
    sta dist_ptr
    lda maze_distances_hi,x
    sta dist_ptr+1
    txa
    clc
    adc #2
    sta enemy_count
    ldx #31
@init:
    txa
    sta slots,x
    dex
    bpl @init
    ldx #31
@shuffle:
    stx random_base
@pick:
    jsr random_byte
    and #31
    cmp random_base
    beq @swap
    bcs @pick
@swap:
    tay
    lda slots,x
    pha
    lda slots,y
    sta slots,x
    pla
    sta slots,y
    dex
    bne @shuffle
    stz object_index
    stz scan_index
@object:
    ldx scan_index
    lda slots,x
    sta candidate_node
    stz direction_index
@separate:
    lda direction_index
    cmp object_index
    beq @accept
    tax
    lda layout_nodes,x
    tax
    lda candidate_node
    jsr maze_distance
    cmp #2
    bcc @skip
    inc direction_index
    bra @separate
@accept:
    ldx object_index
    lda candidate_node
    sta layout_nodes,x
    tay
    lda node_xs,y
    sta layout_x,x
    lda node_ys,y
    sta layout_y,x
    inc object_index
@skip:
    inc scan_index
    lda object_index
    cmp #5
    bne @object
    stz actor_id
    stz scan_index
@guard:
    ldx scan_index
    lda slots,x
    sta candidate_node
    tax
    lda layout_nodes
    jsr maze_distance
    cmp #3
    bcc @next_guard
    ldx #4
@occupied:
    lda candidate_node
    cmp layout_nodes,x
    beq @next_guard
    dex
    bpl @occupied
    ldx actor_id
    lda candidate_node
    sta enemy_nodes,x
    sta enemy_nexts,x
    tay
    lda node_xs,y
    sta enemy_x,x
    lda node_ys,y
    sta enemy_y,x
    stz enemy_dirs,x
    stz enemy_progress,x
    inc actor_id
@next_guard:
    inc scan_index
    lda actor_id
    cmp enemy_count
    bne @guard
    stz route_length
    stz route_length+1
    stz object_index
@leg:
    ldx object_index
    lda layout_nodes,x
    pha
    lda layout_nodes+1,x
    tax
    pla
    jsr maze_distance
    clc
    adc route_length
    sta route_length
    inc object_index
    lda object_index
    cmp #4
    bne @leg
    ldx #5
@pixels:
    asl route_length
    rol route_length+1
    dex
    bne @pixels
    lda #<2000
    sta deadline
    lda #>2000
    sta deadline+1
    ldx level
    lda ms_per_pixel,x
    tax
@budget:
    clc
    lda deadline
    adc route_length
    sta deadline
    lda deadline+1
    adc route_length+1
    sta deadline+1
    dex
    bne @budget
    rts
.endproc

.proc draw_maze
    ldx level
    lda maze_tiles_lo,x
    sta source_ptr
    lda maze_tiles_hi,x
    sta source_ptr+1
    lda #<(TILES+7*40+4)
    sta tile_ptr
    lda #>(TILES+7*40+4)
    sta tile_ptr+1
    lda #16
    sta row_count
@row:
    jsr attribute_pointer
    ldy #0
@tile:
    lda (source_ptr),y
    sta (tile_ptr),y
    cmp #9
    beq @wall
    lda #$a0
    bra @color
@wall:
    lda #$32
@color:
    sta (attr_ptr),y
    iny
    cpy #32
    bne @tile
    clc
    lda source_ptr
    adc #32
    sta source_ptr
    bcc @dest
    inc source_ptr+1
@dest:
    clc
    lda tile_ptr
    adc #40
    sta tile_ptr
    bcc @next
    inc tile_ptr+1
@next:
    dec row_count
    bne @row
    rts
.endproc

.proc check_deadline
    lda LEVEL_TIMER+1
    sta time_work
    lda LEVEL_TIMER+2
    sta time_work+1
    lda LEVEL_TIMER+3
    bne @expired
    lda time_work+1
    cmp deadline+1
    bcc @safe
    bne @expired
    lda time_work
    cmp deadline
    bcc @safe
@expired:
    lda #3
    sta state
    jsr stop_times
    lda #<timeout_message
    sta text_ptr
    lda #>timeout_message
    sta text_ptr+1
    jsr message
    ldx #4
    jsr play_sound
    sec
    rts
@safe:
    clc
    rts
.endproc

.proc near_target
    lda #12
    sta near_limit
    bra within_target
.endproc
.proc near_guard
    lda #32
    sta near_limit
.endproc
.proc within_target
    lda player_x
    sec
    sbc target_x
    bcs @x_positive
    eor #$ff
    clc
    adc #1
@x_positive:
    cmp near_limit
    bcs @far
    lda player_y
    sec
    sbc target_y
    bcs @y_positive
    eor #$ff
    clc
    adc #1
@y_positive:
    cmp near_limit
    bcs @far
    sec
    rts
@far:
    clc
    rts
.endproc

.proc sprite_x
    clc
    adc #32
    sta SPRITES,x
    lda #0
    adc #0
    sta SPRITES+1,x
    rts
.endproc

.proc update_sprites
    ldx #0
    lda player_x
    jsr sprite_x
    lda player_y
    clc
    adc #56
    sta SPRITES+2
    lda ticks
    and #8
    lsr
    lsr
    lsr
    sta SPRITES+3
    lda #4
    ldx state
    cpx #3
    bne @player_color
    lda #7
@player_color:
    sta SPRITES+4
    ldx #8
    lda packet_x
    jsr sprite_x
    lda packet_y
    clc
    adc #56
    sta SPRITES+10
    lda SPRITES+3
    ora #2
    sta SPRITES+11
    stz actor_id
@guard:
    ldy actor_id
    ldx enemy_sprite_offsets,y
    lda enemy_x,y
    jsr sprite_x
    lda enemy_y,y
    clc
    adc #56
    sta SPRITES+2,x
    lda SPRITES+3
    ora #4
    sta SPRITES+3,x
    lda enemy_colors,y
    ldy jam_timer
    beq @color
    lda #11
@color:
    sta SPRITES+4,x
    inc actor_id
    lda actor_id
    cmp enemy_count
    bne @guard
    ldx #56
    lda dock_x
    jsr sprite_x
    lda dock_y
    clc
    adc #56
    sta SPRITES+58
    lda #6
    ldx score
    cpx #3
    bne @dock_pattern
    lda #7
@dock_pattern:
    sta SPRITES+59
    rts
.endproc

.proc stop_times
    stz LEVEL_TIMER
    stz TOTAL_TIMER
    rts
.endproc

.proc draw_times
    lda #<(TILES+5*40)
    sta tile_ptr
    lda #>(TILES+5*40)
    sta tile_ptr+1
    ldx #0
    ldy #0
    jsr draw_clock
    ldx #4
    ldy #17
    jmp draw_clock
.endproc

.proc draw_limit
    lda #<(TILES+21)
    sta tile_ptr
    lda #>(TILES+21)
    sta tile_ptr+1
    lda #<limit_label
    sta text_ptr
    lda #>limit_label
    sta text_ptr+1
    lda #$50
    sta text_color
    jsr print
    lda #<TILES
    sta tile_ptr
    lda #>TILES
    sta tile_ptr+1
    lda deadline
    sta time_work
    lda deadline+1
    sta time_work+1
    stz time_work+2
    lda #18
    sta hud_offset
    jmp format_time
.endproc

; Convert a coherent 24-bit hardware millisecond sample to MM:SS.mmm.
; Decimal place subtraction is bounded (at most nine per place), no drift.
.proc draw_clock
    sty hud_offset
    lda LEVEL_TIMER+1,x     ; Reading low latches both upper bytes in hardware.
    sta time_work
    lda LEVEL_TIMER+2,x
    sta time_work+1
    lda LEVEL_TIMER+3,x
    sta time_work+2
    jmp format_time
.endproc
.proc format_time
    ldx #0
@digit:
    stz time_digit
@compare:
    lda time_work+2
    cmp time_units_hi,x
    bcc @emit
    bne @subtract
    lda time_work+1
    cmp time_units_mid,x
    bcc @emit
    bne @subtract
    lda time_work
    cmp time_units_lo,x
    bcc @emit
@subtract:
    sec
    lda time_work
    sbc time_units_lo,x
    sta time_work
    lda time_work+1
    sbc time_units_mid,x
    sta time_work+1
    lda time_work+2
    sbc time_units_hi,x
    sta time_work+2
    inc time_digit
    bra @compare
@emit:
    lda digit_columns,x
    clc
    adc hud_offset
    tay
    lda time_digit
    ora #'0'
    sta (tile_ptr),y
    inx
    cpx #6
    bne @digit
    ; After removing tens, the remainder is the ones digit already.
    ; Avoid up to nine redundant 24-bit subtractions per clock display.
    ldy hud_offset
    tya
    clc
    adc #16
    tay
    lda time_work
    ora #'0'
    sta (tile_ptr),y
    rts
.endproc

.proc play_sound
    lda note_lo,x
    sta TONE_L
    sta TONE_R
    lda note_hi,x
    sta TONE_L+1
    sta TONE_R+1
    lda #6
    sta TONE_L+2
    sta TONE_R+2
    lda #1
    sta TONE_L+3
    sta TONE_R+3
    lda #8
    cpx #3
    bcc @duration
    lda #24
@duration:
    sta sound_timer
    rts
.endproc

.proc advance_sound
    lda sound_timer
    beq @done
    dec sound_timer
    bne @done
    stz TONE_L+3
    stz TONE_R+3
@done:
    rts
.endproc

.proc report_state
    lda score
    asl
    asl
    asl
    asl
    ora state
    ora #$80
    sta DIAGNOSTIC
    rts
.endproc

.proc irq_handler
    pha
    inc ticks
    lda #1
    sta IRQ_PENDING
    pla
    rti
.endproc
.proc nmi_handler
    rti
.endproc

.segment "RODATA"
title:        .asciiz "CIRCUIT COURIER"
subtitle:     .asciiz "DELIVER DATA. DODGE THE GUARD."
instructions: .asciiz "ARROWS STEER  Z JAM  X SLOW"
score_label:  .asciiz "PACKETS 0/3"
level_label:  .asciiz "LEVEL 1/4"
time_label:   .asciiz "TIME 00:00.000  TOTAL 00:00.000"
prompt:       .asciiz "PRESS A TO CONNECT"
lost_message: .asciiz "LINK LOST - A RETRY"
timeout_message: .asciiz "TOO SLOW - A RETRY"
limit_label: .asciiz "BEAT 00:00.000"
clear_message_text: .asciiz "CIRCUIT CLEAR - A NEXT"
win_message:  .asciiz "ALL DELIVERED! A REPLAY"
ms_per_pixel: .byte 18,17,16,15
direction_bits: .byte 1,2,4,8
direction_delta: .byte 0,1,255,0,8,0,0,0,248
opposite_dir: .byte 0,2,1,0,8,0,0,0,4
enemy_sprite_offsets: .byte 16,24,32,40,48
enemy_colors: .byte 7,8,6,9,13
patrol_nodes: .byte 0,7,31,24
jam_cooldowns: .byte 150,180,210,240
node_xs: .byte 0,32,64,96,128,160,192,224,0,32,64,96,128,160,192,224
         .byte 0,32,64,96,128,160,192,224,0,32,64,96,128,160,192,224
node_ys: .byte 0,0,0,0,0,0,0,0,32,32,32,32,32,32,32,32
         .byte 64,64,64,64,64,64,64,64,96,96,96,96,96,96,96,96
guards_label: .asciiz "GUARDS 2"
jam_ready: .asciiz "JAM READY - Z TO PULSE   "
jam_wait: .asciiz "JAM RECHARGING          "
jam_active: .asciiz "NETWORK JAMMED          "
level_colors_lo: .byte <$277,<$637,<$653,<$357
level_colors_hi: .byte >$277,>$637,>$653,>$357
level_names_lo: .byte <level_1,<level_2,<level_3,<level_4
level_names_hi: .byte >level_1,>level_2,>level_3,>level_4
level_1: .asciiz "1 - BOOT SECTOR               "
level_2: .asciiz "2 - MIRROR BUS                "
level_3: .asciiz "3 - REVERSE FLOW              "
level_4: .asciiz "4 - CROSS CIRCUIT             "
digit_columns: .byte 8,9,11,12,14,15
time_units_lo:  .byte <600000,<60000,<10000,<1000,<100,<10
time_units_mid: .byte >600000,>60000,>10000,>1000,>100,>10
time_units_hi:  .byte (600000>>16),(60000>>16),0,0,0,0
note_lo:      .byte <1396,<1759,<2092,<2793,<347
note_hi:      .byte >1396,>1759,>2092,>2793,>347
; RGB444, little-endian per entry.
colors: .word $012,$001,$245,$277,$7ec,$fe9,$f94,$e67
        .word $a7b,$37b,$234,$acd,$467,$ca6,$fbc,$efe

.include "maze-data.inc"

.segment "VECTORS"
    .word nmi_handler, reset, irq_handler
