;=============================================================================
; SUPER PAC-MAN (Namco, 1982) - main CPU (MC6809E) - annotated disassembly
; MAME driver: namco/mappy.cpp, set "superpac" (ROMs sp1-2.1c at $C000,
; sp1-1.1b at $E000). Labels: <description>_<hex address in lower case>.
; All original addresses / bytes are kept, except the fixed spots listed
; at the end of this header. Tool tags ([function_address], [no_return],
; [indirect_jump], [global]...) are kept.
;=============================================================================
;
; MEMORY MAP (MAME superpac_main_map - NOTE: the map pasted below the header
; is the Mappy / Dig Dug II one, Super Pac-Man differs):
;  $0000-$03FF  video RAM tile codes (36x28 rotated tilemap: next column
;               on screen = address - $20). $0400-$07FF colour codes.
;  $0800-$1FFF  work RAM with 3 embedded sprite areas:
;               $0F80-$0FFF code/colour, $1780-$17FF y/x, $1F80-$1FFF flags
;               (the game builds them at $0F00/$1700/$1F00 and the IRQ copies
;               them: double buffer). 64 sprites, 2 bytes each.
;  $1000-$10FF  direct page (DP = $10 : "<$8B" means $108B)
;  $1100-$112F  6 task slots x 8 bytes      $1138-$115F high score table
;  $0810-$0F0F, $1610-$170F  object records ($20 bytes each)
;  $2000        flip screen
;  $4000-$43FF  RAM shared with the sound CPU (15XX sound chip registers);
;               $4040-$4057: one byte per sound effect, write 1 to play it
;  $4800-$480F / $4810-$481F  Namco 56XX custom I/O chips (inputs, dips)
;  $5000-$500F  LS259 latch (A0 = data): IRQ enables, sound, I/O & sub CPU reset
;  $8000        watchdog       $C000-$FFFF ROM
;
;=============================================================================
; THE TASK SYSTEM (coroutines) - READ THIS BEFORE PORTING
;=============================================================================
; Unlike many Namco games the tasks do NOT run in the IRQ. The IRQ
; (irq_vblank_e2d6) only does hardware work and sets a flag; the main loop
; (main_loop_e211) waits for it and runs the tasks once per frame.
;
; Level 1 - 6 SLOTS at $1100 (8 bytes: +0 resume PC, +2 wait counter,
;   +4 RUNNER). The main loop calls JSR [4,U] for slots 1-5; the runner
;   is normally runner_resume_f0de (JSR [,U]) or task_nop_rts_e2ba (paused):
;     slot 0 $1100 : freeze/rack test only
;     slot 1 $1108 : game flow (attract, credit, game, death...) - the PC
;                    is replaced to change phase (e.g. pacman_died_ea60)
;     slot 2 $1110 : object_manager_task_f085 (runs all the objects)
;     slot 3 $1118 : score display          slot 4 $1120
;     slot 5 $1128 : frightened timer / bonus
; Level 2 - OBJECTS: records of $20 bytes in $0810-$0F0F and $1610-$170F
;   (see object_manager_task_f085 for the layout). Each has the same
;   +0 resume PC / +2 counter / +4 runner fields.
; RUNNERS (in +4): runner_resume_f0de (run the coroutine),
;   runner_resume_and_draw_f0fb (run + update the sprite),
;   runner_draw_sprite_f101 (sprite only), runner_kill_object_f0e5,
;   task_nop_rts_e2ba, task_idle_fd3a...
; A coroutine is entered with U = its record. It gives back control with:
;   JSR task_yield_e2b4      : continue here next frame
;   LDD #n / JSR task_wait_init_e2bb / ... / JSR task_wait_e2c4
;                            : wait n frames (the code between the two
;                              JSRs is executed every frame)
;   RTS                      : back to the runner, next frame restarts at
;                              the last saved PC
;   a new state             : LDD #addr / STD ,U  (next frame starts there)
; PORTING PITFALLS
;  1. Only the PC is saved (in ,U): the yield must happen at the top level
;     of the coroutine (no JSR nesting, nothing pushed) and registers are
;     lost - everything is kept in the record fields.
;  2. The PC is stored as a 16-bit ROM address and compared with ROM
;     addresses (e.g. CMPX #$E844, the anti-tampering CMP of $E28A with
;     #$E3E6). In a port those must become the new addresses/labels.
;  3. intermission_run_c762 and name entry pop their return address into
;     $10E4 and continue with JMP [$10E4] several frames later.
;  4. print_inline_string_eec7/eec3 read the string that FOLLOWS the JSR
;     in the ROM (ends with $00) and jump after it: the string bytes are
;     NOT in this listing (gaps) - take them from the ROM.
;  5. Anti-tampering checks: 'NAMCO ' at $C112, default high scores at
;     $EB58.. and $E28A. A port that moves data must patch or remove them.
;
; FIXES MADE IN THIS FILE (the original listing was out of sync):
;  $E788-$E78B, $EA2E, $EB1B, $EBC5-$EBCD, $EBE6, $EE54-$EE57, $EE5F-$EE63:
;     end of inline strings disassembled as code -> dc.b + real code
;  $F48F: last byte of a table, the pellet task starts at $F490
;  $F86D-$F870: sprite code table, not code
;  $C2C8, $CB3C, $CBAC, $F858: [function_address] removed - these values
;     are screen coordinates / a data table, not code addresses.
;=============================================================================

; super pacman is the exact same hw as dig dug 2!!
;	map(0x0000, 0x0fff).ram().w(FUNC(mappy_state::mappy_videoram_w)).share("videoram");
;	map(0x1000, 0x27ff).ram().share("spriteram");   // work RAM with embedded sprite RAM
;   sprites start at stack_top_1780 with 3 buffers of $800 bytes that hold attributes, code and coords
;   64 sprites can be displayed total
;	map(0x3800, 0x3fff).w(FUNC(mappy_state::mappy_scroll_w));   // scroll not used
;	map(0x4000, 0x43ff).rw(m_namco_15xx, FUNC(namco_15xx_device::sharedram_r), FUNC(namco_15xx_device::sharedram_w));   // shared RAM with the sound CPU
;	map(0x4800, 0x480f).rw("namcoio_1", FUNC(namcoio_device::read), FUNC(namcoio_device::write));   // custom I/O chips interface
;	map(0x4810, 0x481f).rw("namcoio_2", FUNC(namcoio_device::read), FUNC(namcoio_device::write));   // custom I/O chips interface
;	map(0x5000, 0x500f).w("mainlatch", FUNC(ls259_device::write_a0));   // various control bits
;	map(0x8000, 0x8000).w("watchdog", FUNC(watchdog_timer_device::reset_w));
;	map(0x8000, 0xffff).rom();  // only c000-ffff here

;#define NAMCO_56IN0\
;	PORT_START("P1")    /* 56XX #0 pins 22-29 */\
;	PORT_BIT( 0x01, IP_ACTIVE_LOW, IPT_JOYSTICK_UP ) PORT_4WAY\
;	PORT_BIT( 0x02, IP_ACTIVE_LOW, IPT_JOYSTICK_RIGHT ) PORT_4WAY\
;	PORT_BIT( 0x04, IP_ACTIVE_LOW, IPT_JOYSTICK_DOWN ) PORT_4WAY\
;	PORT_BIT( 0x08, IP_ACTIVE_LOW, IPT_JOYSTICK_LEFT ) PORT_4WAY\
;	PORT_START("P2")    /* 56XX #0 pins 22-29 */\
;	PORT_BIT( 0x01, IP_ACTIVE_LOW, IPT_JOYSTICK_UP ) PORT_4WAY PORT_COCKTAIL\
;	PORT_BIT( 0x02, IP_ACTIVE_LOW, IPT_JOYSTICK_RIGHT ) PORT_4WAY PORT_COCKTAIL\
;	PORT_BIT( 0x04, IP_ACTIVE_LOW, IPT_JOYSTICK_DOWN ) PORT_4WAY PORT_COCKTAIL\
;	PORT_BIT( 0x08, IP_ACTIVE_LOW, IPT_JOYSTICK_LEFT ) PORT_4WAY PORT_COCKTAIL
;
;#define NAMCO_5XIN0\
;	PORT_START("P1") /* 56XX #0 pins 22-29 */\
;	PORT_BIT( 0x01, IP_ACTIVE_LOW, IPT_JOYSTICK_UP ) PORT_8WAY\
;	PORT_BIT( 0x02, IP_ACTIVE_LOW, IPT_JOYSTICK_RIGHT ) PORT_8WAY\
;	PORT_BIT( 0x04, IP_ACTIVE_LOW, IPT_JOYSTICK_DOWN ) PORT_8WAY\
;	PORT_BIT( 0x08, IP_ACTIVE_LOW, IPT_JOYSTICK_LEFT ) PORT_8WAY\
;	PORT_START("P2") /* 56XX #0 pins 22-29 */\
;	PORT_BIT( 0x01, IP_ACTIVE_LOW, IPT_JOYSTICK_UP ) PORT_8WAY PORT_COCKTAIL\
;	PORT_BIT( 0x02, IP_ACTIVE_LOW, IPT_JOYSTICK_RIGHT ) PORT_8WAY PORT_COCKTAIL\
;	PORT_BIT( 0x04, IP_ACTIVE_LOW, IPT_JOYSTICK_DOWN ) PORT_8WAY PORT_COCKTAIL\
;	PORT_BIT( 0x08, IP_ACTIVE_LOW, IPT_JOYSTICK_LEFT ) PORT_8WAY PORT_COCKTAIL
;
;#define NAMCO_56IN1\
;	PORT_START("BUTTONS")   /* 56XX #0 pins 30-33 and 38-41 */\
;	PORT_BIT( 0x01, IP_ACTIVE_LOW, IPT_BUTTON1 )\
;	PORT_BIT( 0x02, IP_ACTIVE_LOW, IPT_BUTTON1 ) PORT_COCKTAIL\
;	PORT_BIT( 0x04, IP_ACTIVE_LOW, IPT_START1 )\
;	PORT_BIT( 0x08, IP_ACTIVE_LOW, IPT_START2 )\
;	PORT_START("COINS") /* 56XX #0 pins 30-33 and 38-41 */\
;	PORT_BIT( 0x01, IP_ACTIVE_LOW, IPT_COIN1 )\
;	PORT_BIT( 0x02, IP_ACTIVE_LOW, IPT_COIN2 )\
;	PORT_BIT( 0x04, IP_ACTIVE_LOW, IPT_UNUSED )\
;	PORT_BIT( 0x08, IP_ACTIVE_LOW, IPT_SERVICE1 )
;
;#define NAMCO_56DSW0\
;	PORT_START("DSW0")  /* 56XX #1 pins 30-33 */\
;	PORT_BIT( 0x01, IP_ACTIVE_LOW, IPT_UNUSED )\
;	PORT_BIT( 0x02, IP_ACTIVE_LOW, IPT_UNUSED )\
;	PORT_DIPNAME( 0x04, 0x04, DEF_STR( Cabinet ) )\
;	PORT_DIPSETTING(    0x04, DEF_STR( Upright ) )\
;	PORT_DIPSETTING(    0x00, DEF_STR( Cocktail ) )\
;	PORT_SERVICE( 0x08, IP_ACTIVE_LOW )
;
;static INPUT_PORTS_START( superpac )
;	NAMCO_56IN0
;	NAMCO_56IN1
;	NAMCO_56DSW0
;
;	PORT_START("DSW1")  // 56XX #1 pins 22-29
;	PORT_DIPNAME( 0x0f, 0x0f, DEF_STR( Difficulty ) )   PORT_DIPLOCATION("SW1:1,2,3,4")
;	PORT_DIPSETTING(    0x0f, "Rank 0-Normal" )
;	PORT_DIPSETTING(    0x0e, "Rank 1-Easiest" )
;	PORT_DIPSETTING(    0x0d, "Rank 2" )
;	PORT_DIPSETTING(    0x0c, "Rank 3" )
;	PORT_DIPSETTING(    0x0b, "Rank 4" )
;	PORT_DIPSETTING(    0x0a, "Rank 5" )
;	PORT_DIPSETTING(    0x09, "Rank 6-Medium" )
;	PORT_DIPSETTING(    0x08, "Rank 7" )
;	PORT_DIPSETTING(    0x07, "Rank 8-Default" )
;	PORT_DIPSETTING(    0x06, "Rank 9" )
;	PORT_DIPSETTING(    0x05, "Rank A" )
;	PORT_DIPSETTING(    0x04, "Rank B-Hardest" )
;	PORT_DIPSETTING(    0x03, "Rank C-Easy Auto" )
;	PORT_DIPSETTING(    0x02, "Rank D-Auto" )
;	PORT_DIPSETTING(    0x01, "Rank E-Auto" )
;	PORT_DIPSETTING(    0x00, "Rank F-Hard Auto" )
;	PORT_DIPNAME( 0x30, 0x30, DEF_STR( Coin_B ) )       PORT_DIPLOCATION("SW1:5,6")
;	PORT_DIPSETTING(    0x10, DEF_STR( 2C_1C ) )
;	PORT_DIPSETTING(    0x30, DEF_STR( 1C_1C ) )
;	PORT_DIPSETTING(    0x00, DEF_STR( 2C_3C ) )
;	PORT_DIPSETTING(    0x20, DEF_STR( 1C_2C ) )
;	PORT_DIPNAME( 0x40, 0x40, DEF_STR( Demo_Sounds ) )  PORT_DIPLOCATION("SW1:7")
;	PORT_DIPSETTING(    0x00, DEF_STR( Off ) )
;	PORT_DIPSETTING(    0x40, DEF_STR( On ) )
;	// When Freeze is on, press P1 button 1 to skip levels
;	PORT_DIPNAME( 0x80, 0x80, "Freeze / Rack Test (Cheat)" ) PORT_TOGGLE PORT_DIPLOCATION("SW1:8")
;	PORT_DIPSETTING(    0x80, DEF_STR( Off ) )
;	PORT_DIPSETTING(    0x00, DEF_STR( On ) )
;
;	PORT_START("DSW2")  // 56XX #1 pins 38-41 multiplexed
;	PORT_DIPNAME( 0x07, 0x07, DEF_STR( Coin_A ) )       PORT_DIPLOCATION("SW2:1,2,3")
;	PORT_DIPSETTING(    0x00, DEF_STR( 3C_1C ) )
;	PORT_DIPSETTING(    0x02, DEF_STR( 2C_1C ) )
;	PORT_DIPSETTING(    0x07, DEF_STR( 1C_1C ) )
;	PORT_DIPSETTING(    0x01, DEF_STR( 2C_3C ) )
;	PORT_DIPSETTING(    0x06, DEF_STR( 1C_2C ) )
;	PORT_DIPSETTING(    0x05, DEF_STR( 1C_3C ) )
;	PORT_DIPSETTING(    0x04, DEF_STR( 1C_6C ) )
;	PORT_DIPSETTING(    0x03, DEF_STR( 1C_7C ) )
;	PORT_DIPNAME( 0x38, 0x38, DEF_STR( Bonus_Life ) )   PORT_DIPLOCATION("SW2:4,5,6")
;	PORT_DIPSETTING(    0x08, "30k Only" )                  PORT_CONDITION("DSW2",0xc0,NOTEQUALS,0x00)
;	PORT_DIPSETTING(    0x30, "30k & 80k Only" )            PORT_CONDITION("DSW2",0xc0,NOTEQUALS,0x00)
;	PORT_DIPSETTING(    0x20, "30k, 80k & Every 80k" )      PORT_CONDITION("DSW2",0xc0,NOTEQUALS,0x00)
;	PORT_DIPSETTING(    0x38, "30k & 100k Only" )           PORT_CONDITION("DSW2",0xc0,NOTEQUALS,0x00)
;	PORT_DIPSETTING(    0x18, "30k, 100k & Every 100k" )    PORT_CONDITION("DSW2",0xc0,NOTEQUALS,0x00)
;	PORT_DIPSETTING(    0x28, "30k & 120k Only" )           PORT_CONDITION("DSW2",0xc0,NOTEQUALS,0x00)
;	PORT_DIPSETTING(    0x10, "30k, 120k & Every 120k" )    PORT_CONDITION("DSW2",0xc0,NOTEQUALS,0x00)
;	PORT_DIPSETTING(    0x10, "30k Only" )                  PORT_CONDITION("DSW2",0xc0,EQUALS,0x00) // Manual shows 100k only, Test Mode shows 30k which is what we use
;	PORT_DIPSETTING(    0x38, "30k & 100k Only" )           PORT_CONDITION("DSW2",0xc0,EQUALS,0x00)
;	PORT_DIPSETTING(    0x20, "30k, 100k & Every 100k" )    PORT_CONDITION("DSW2",0xc0,EQUALS,0x00)
;	PORT_DIPSETTING(    0x30, "30k & 120k Only" )           PORT_CONDITION("DSW2",0xc0,EQUALS,0x00)
;	PORT_DIPSETTING(    0x08, "40k Only" )                  PORT_CONDITION("DSW2",0xc0,EQUALS,0x00)
;	PORT_DIPSETTING(    0x28, "40k & 120k Only" )           PORT_CONDITION("DSW2",0xc0,EQUALS,0x00)
;	PORT_DIPSETTING(    0x18, "40k, 120k & Every 120k" )    PORT_CONDITION("DSW2",0xc0,EQUALS,0x00)
;	PORT_DIPSETTING(    0x00, DEF_STR( None ) )
;	PORT_DIPNAME( 0xc0, 0xc0, DEF_STR( Lives ) )        PORT_DIPLOCATION("SW2:7,8")
;	PORT_DIPSETTING(    0x80, "1" )
;	PORT_DIPSETTING(    0x40, "2" )
;	PORT_DIPSETTING(    0xc0, "3" )
;	PORT_DIPSETTING(    0x00, "5" )
;INPUT_PORTS_END

;-------------------------------------------------------------- hardware / RAM equates
watchdog_8000 = $8000                           ; watchdog reset
flip_screen_2000 = $2000                        ; flip screen (bit 0)
namco_io1_4800 = $4800                          ; 56XX #1: coins, joysticks, buttons (16 nibbles)
namco_io1_mode_4808 = $4808                     ; 56XX #1 mode / command register
namco_io2_4810 = $4810                          ; 56XX #2: dip switches (16 nibbles)
namco_io2_mode_4818 = $4818                     ; 56XX #2 mode / command register
latch_sub_irq_off_5000 = $5000                  ; LS259 bit0=0 : sound CPU IRQ disable
latch_sub_irq_on_5001 = $5001                   ; LS259 bit0=1 : sound CPU IRQ enable
latch_main_irq_off_5002 = $5002                 ; LS259 bit1=0 : main IRQ disable (also acknowledges)
latch_main_irq_on_5003 = $5003                  ; LS259 bit1=1 : main IRQ enable
latch_sound_off_5006 = $5006                    ; LS259 bit3=0 : sound disable
latch_sound_on_5007 = $5007                     ; LS259 bit3=1 : sound enable
latch_io_reset_5008 = $5008                     ; LS259 bit4=0 : custom I/O chips held in reset
latch_io_run_5009 = $5009                       ; LS259 bit4=1 : custom I/O chips running
latch_sub_reset_500a = $500A                    ; LS259 bit5=0 : sound CPU held in reset
latch_sub_run_500b = $500B                      ; LS259 bit5=1 : sound CPU running
pacman_object_1630 = $1630                      ; Pac-Man object record (see object layout)
pacman_y_163c = $163C                           ; Pac-Man position y ($163D = x)
task_slot1_1108 = $1108                         ; task slot 1 (game flow)
task_slot2_1110 = $1110                         ; task slot 2 (object manager)
task_slot3_1118 = $1118                         ; task slot 3 (score display)
task_slot5_1128 = $1128                         ; task slot 5 (frightened timer)
;-------------------------------------------------------------- direct page variables ($10xx, used as <$xx)
;   <$00  score (3 BCD bytes, current player)
;   <$01  score mid
;   <$02  score low
;   <$03  level (BCD)
;   <$04  next extra-life score
;   <$05  next extra-life score lo
;   <$06  extra lives awarded
;   <$07  lives left
;   <$10  bonus item type of the level
;   <$11  item history count
;   <$12  rank table index
;   <$13  round number (BCD)
;   <$14  maze colour
;   <$18  intermission schedule index
;   <$19  intermission counter
;   <$1A  levels played (max 12)
;   <$1B  current rank
;   <$1C  rank frozen after death
;   <$1D  rank step
;   <$80  vblank flag (set by IRQ)
;   <$81  frame counter
;   <$82  2-player game flag
;   <$83  cocktail cabinet
;   <$84  current player (0/1)
;   <$85  screen flipped (cocktail P2)
;   <$86  player-up blink control
;   <$8A  ghosts eaten in a row
;   <$8B  game sounds enabled (0 in attract)
;   <$8C  bonus stage timer on
;   <$8D  bonus stage timer sub-count
;   <$8E  bonus stage time (BCD)
;   <$8F  bonus stage time lo
;   <$90  fruits left
;   <$91  power pellets left
;   <$92  frames since level start
;   <$93  frames since level start lo
;   <$94  level parameter index
;   <$95  ghost release table index
;   <$96  bonus stage flag
;   <$97  elroy ghost index limit
;   <$98  elroy threshold 1
;   <$99  elroy threshold 2
;   <$9A  super Pac-Man duration
;   <$9C  frightened duration
;   <$9E  Pac-Man speed
;   <$A0  ghost speed normal
;   <$A2  ghost speed elroy 1
;   <$A4  ghost speed elroy 2
;   <$A6  ghost speed tunnel
;   <$A8  ghost eyes speed
;   <$AA  intermission number (0 = none)
;   <$AB  input mode 0=live 1=record 2=demo playback
;   <$AC  current controls (active high)
;   <$AD  demo recording frame count
;   <$AE  demo data pointer
;   <$C0  credits
;   <$C1  credits needed / play
;   <$C2  controls read by the I/O chip
;   <$C3  previous controls
;   <$C4  DSW0 / service bits
;   <$C5  DSW2 (coin A, bonus, lives)
;   <$C6  DSW1 (rank, coin B, demo sound, freeze)
;   <$C7  attract flag
;   <$CF  bonus life setting
;   <$D0  lives setting
;   <$D1  difficulty rank setting
;   <$D3  demo sounds
;   <$D4  first extra life (BCD)
;   <$D6  extra life every (BCD)
;   <$E4  saved return address
;   <$E8  service mode flag
;   <$E9  sound test index
;   <$EC  random seed
;   <$ED  random seed lo
;   <$F8  temp / loop counter

;----------------------------------------------------------------------------
; COLD START OF THE ATTRACT MODE (entered from task_power_up_e3e6 and after
; every game/demo). Runs as the task of slot 1 ($1108): every
; task_yield / task_wait returns to the main loop and comes back here.
; Init high scores, sounds off, object manager on, maze colour 4.
;----------------------------------------------------------------------------
cold_start_attract_c000:
C000: BD EB 3B    JSR    init_hiscore_table_eb3b

attract_loop_c003:
C003: 4F          CLRA
C004: 97 8B       STA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
C006: 97 AB       STA    <$AB                   ; <$AB=input mode 0=live 1=record 2=demo playback
C008: 4C          INCA
C009: 97 C7       STA    <$C7                   ; <$C7=attract flag
C00B: BD E2 9E    JSR    enable_object_tasks_e29e
C00E: BD E2 B4    JSR    task_yield_e2b4
C011: 86 04       LDA    #$04
C013: 97 14       STA    <$14                   ; <$14=maze colour
C015: BD EE 06    JSR    clear_screen_and_status_ee06
C018: BD C1 03    JSR    print_copyright_c103
C01B: CE 00 8B    LDU    #$008B
C01E: BD C1 35    JSR    draw_title_screen_c135
C021: CE 02 D2    LDU    #$02D2
C024: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $C027-$C02F (bytes not in this listing, ends with $00), then continues after it

C030: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $C033-$C038 (bytes not in this listing, ends with $00), then continues after it

;----------------------------------------------------------------------------
; Attract sequence: character roll call (keys, fruits, pellets, Pac-Man and
; ghosts appear as objects), title logo, then a demo game.
;----------------------------------------------------------------------------
attract_roll_call_c039:
C039: BD C1 6C    JSR    attract_init_keys_c16c
C03C: BD C1 D6    JSR    attract_init_fruits_c1d6
C03F: BD C2 4C    JSR    attract_init_super_pellet_c24c
C042: BD C2 56    JSR    attract_init_power_pellet_c256
C045: BD C2 A4    JSR    attract_init_pacman_c2a4
C048: CC 07 08    LDD    #$0708
C04B: BD E2 BB    JSR    task_wait_init_e2bb
C04E: BD E2 C4    JSR    task_wait_e2c4
C051: BD EE 06    JSR    clear_screen_and_status_ee06
C054: BD C0 85    JSR    draw_title_logo_c085
C057: BD C1 03    JSR    print_copyright_c103
C05A: CC 00 B4    LDD    #$00B4
C05D: BD E2 BB    JSR    task_wait_init_e2bb
C060: BD E2 C4    JSR    task_wait_e2c4
C063: BD EE 06    JSR    clear_screen_and_status_ee06
C066: BD C0 85    JSR    draw_title_logo_c085
C069: CE 02 50    LDU    #$0250
C06C: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $C06F-$C076 (bytes not in this listing, ends with $00), then continues after it

;----------------------------------------------------------------------------
; (was 'attract_c077') wait 3 s then play the demo game. NOTE: 'LDD -$10,U' is dead (D is reloaded).
;----------------------------------------------------------------------------
attract_start_demo_c077:
C077: EC 50       LDD    -$10,U
C079: CC 00 B4    LDD    #$00B4
C07C: BD E2 BB    JSR    task_wait_init_e2bb
C07F: BD E2 C4    JSR    task_wait_e2c4
C082: 7E C4 45    JMP    demo_game_c445

;----------------------------------------------------------------------------
; Draw the title logo: pairs (tile, colour) from the table at $C0A3 into video RAM $0146.. (colour = tile addr + $400).
;----------------------------------------------------------------------------
draw_title_logo_c085:
C085: 8E C0 A3    LDX    #$C0A3
C088: CE 01 46    LDU    #$0146
C08B: C6 04       LDB    #$04
C08D: A6 80       LDA    ,X+
C08F: A7 C0       STA    ,U+
C091: A6 80       LDA    ,X+
C093: A7 C9 03 FF STA    $03FF,U
C097: 5A          DECB
C098: 26 F3       BNE    $C08D
C09A: 33 C8 1C    LEAU   $1C,U
C09D: 8C C1 03    CMPX   #$C103
C0A0: 26 E9       BNE    $C08B
C0A2: 39          RTS

print_copyright_c103:
C103: CE 03 1B    LDU    #$031B
C106: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $C109-$C11F (bytes not in this listing, ends with $00), then continues after it

draw_attract_text_c120:
C120: CC 02 07    LDD    #$0207
C123: BD FE 0F    JSR    fill_row_fe0f
C126: CE 02 5E    LDU    #$025E
C129: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $C12C-$C134 (bytes not in this listing, ends with $00), then continues after it

draw_title_screen_c135:
C135: CC C4 D4    LDD    #$C4D4
C138: B7 03 6B    STA    $036B
C13B: F7 03 6E    STB    $036E
C13E: CC C5 D5    LDD    #$C5D5
C141: B7 00 8B    STA    >$008B
C144: F7 00 8E    STB    >$008E
C147: CC C0 16    LDD    #$C016
C14A: CE 03 4B    LDU    #$034B
C14D: BD FE 0F    JSR    fill_row_fe0f
C150: CC C1 16    LDD    #$C116
C153: CE 03 4E    LDU    #$034E
C156: BD FE 0F    JSR    fill_row_fe0f
C159: 86 09       LDA    #$09
C15B: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
C15D: 8E F0 71    LDX    #$F071
C160: BD F0 0A    JSR    table_screen_address_f00a
C163: A7 C4       STA    ,U
C165: A7 C5       STA    B,U
C167: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
C169: 2A F2       BPL    $C15D
C16B: 39          RTS

;----------------------------------------------------------------------------
; Attract: create 10 key objects in $0810.. (one per $20 bytes) moving in a
; column; their state machine is attract_key_task_c19a.
;----------------------------------------------------------------------------
attract_init_keys_c16c:
C16C: CE 08 10    LDU    #$0810
C16F: C6 09       LDB    #$09
C171: E7 56       STB    -$A,U
C173: 86 14       LDA    #$14
C175: 3D          MUL
C176: 1F 98       TFR    B,A
C178: 8B 28       ADDA   #$28
C17A: C6 48       LDB    #$48
C17C: ED 4C       STD    $C,U
C17E: CC 00 40    LDD    #$0040
C181: ED 49       STD    $9,U
C183: 86 24       LDA    #$24
C185: A7 4B       STA    $B,U
C187: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
C18A: ED 44       STD    $4,U
C18C: CC C1 9A    LDD    #$c19a                 ; [function_address] ; -> attract_key_task_c19a
C18F: ED C4       STD    ,U
C191: E6 56       LDB    -$A,U
C193: 33 C8 20    LEAU   $20,U
C196: 5A          DECB
C197: 2A D8       BPL    $C171
C199: 39          RTS

;----------------------------------------------------------------------------
; Attract key object: waits until Pac-Man touches it, sound, shows the key then disappears.
;----------------------------------------------------------------------------
attract_key_task_c19a:
C19A: CC F0 DE    LDD    #$f0de                 ; [function_address] ; -> runner_resume_f0de
C19D: ED 44       STD    $4,U
C19F: BD E2 B4    JSR    task_yield_e2b4
C1A2: BD F6 AC    JSR    collision_with_pacman_f6ac
C1A5: 25 01       BCS    $C1A8
C1A7: 39          RTS
C1A8: 96 D3       LDA    <$D3                   ; <$D3=demo sounds
C1AA: B7 40 49    STA    $4049                  ; SOUND: key eaten
C1AD: CC 7C 02    LDD    #$7C02
C1B0: ED 4A       STD    $A,U
C1B2: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
C1B5: ED 44       STD    $4,U
C1B7: 8E F0 71    LDX    #$F071
C1BA: A6 56       LDA    -$A,U
C1BC: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
C1BE: BD F0 0A    JSR    table_screen_address_f00a
C1C1: 86 20       LDA    #$20
C1C3: A7 C4       STA    ,U
C1C5: A7 C5       STA    B,U
C1C7: CC 00 20    LDD    #$0020
C1CA: BD E2 BB    JSR    task_wait_init_e2bb
C1CD: BD E2 C4    JSR    task_wait_e2c4
C1D0: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C1D3: ED 44       STD    $4,U
C1D5: 39          RTS

attract_init_fruits_c1d6:
C1D6: CE 09 F0    LDU    #$09F0
C1D9: C6 08       LDB    #$08
C1DB: E7 56       STB    -$A,U
C1DD: 86 14       LDA    #$14
C1DF: 3D          MUL
C1E0: 1F 98       TFR    B,A
C1E2: 8B 30       ADDA   #$30
C1E4: C6 68       LDB    #$68
C1E6: ED 4C       STD    $C,U
C1E8: 6F 49       CLR    $9,U
C1EA: C6 08       LDB    #$08
C1EC: E0 56       SUBB   -$A,U
C1EE: C1 04       CMPB   #$04
C1F0: 24 08       BCC    $C1FA
C1F2: 1F 98       TFR    B,A
C1F4: CB 10       ADDB   #$10
C1F6: 8B 44       ADDA   #$44
C1F8: 20 03       BRA    $C1FD
C1FA: CC 7E 02    LDD    #$7E02
C1FD: ED 4A       STD    $A,U
C1FF: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
C202: ED 44       STD    $4,U
C204: CC C2 12    LDD    #$C212                 ; [function_address] ; -> attract_fruit_task_c212
C207: ED C4       STD    ,U
C209: E6 56       LDB    -$A,U
C20B: 33 C8 20    LEAU   $20,U
C20E: 5A          DECB
C20F: 2A CA       BPL    $C1DB
C211: 39          RTS

attract_fruit_task_c212:
C212: CC F0 DE    LDD    #$f0de                 ; [function_address] ; -> runner_resume_f0de
C215: ED 44       STD    $4,U
C217: BD E2 B4    JSR    task_yield_e2b4
C21A: BD F6 AC    JSR    collision_with_pacman_f6ac
C21D: 25 01       BCS    $C220
C21F: 39          RTS
C220: 96 D3       LDA    <$D3                   ; <$D3=demo sounds
C222: B7 40 4A    STA    $404A                  ; SOUND: fruit eaten
C225: 86 80       LDA    #$80
C227: A0 56       SUBA   -$A,U
C229: 81 80       CMPA   #$80
C22B: 27 06       BEQ    $C233
C22D: 81 7C       CMPA   #$7C
C22F: 25 03       BCS    $C234
C231: 86 7E       LDA    #$7E
C233: 4A          DECA
C234: C6 02       LDB    #$02
C236: ED 4A       STD    $A,U
C238: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
C23B: ED 44       STD    $4,U
C23D: CC 00 20    LDD    #$0020
C240: BD E2 BB    JSR    task_wait_init_e2bb
C243: BD E2 C4    JSR    task_wait_e2c4
C246: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C249: ED 44       STD    $4,U
C24B: 39          RTS

attract_init_super_pellet_c24c:
C24C: CE 0D F0    LDU    #$0DF0
C24F: 8E 80 BC    LDX    #$80BC
C252: 86 01       LDA    #$01
C254: 20 07       BRA    attract_init_pellet_common_c25d

attract_init_power_pellet_c256:
C256: CE 0D D0    LDU    #$0DD0
C259: 8E 80 94    LDX    #$8094
C25C: 4F          CLRA

attract_init_pellet_common_c25d:
C25D: BD F4 6C    JSR    pellet_setup_f46c
C260: CC C2 66    LDD    #$C266                 ; [function_address] ; -> attract_pellet_task_c266
C263: ED C4       STD    ,U
C265: 39          RTS

attract_pellet_task_c266:
C266: A6 55       LDA    -$B,U
C268: 27 1A       BEQ    $C284
C26A: BD F4 C0    JSR    super_pellet_colour_cycle_f4c0
C26D: BD F6 AC    JSR    collision_with_pacman_f6ac
C270: 25 01       BCS    $C273
C272: 39          RTS
C273: 96 D3       LDA    <$D3                   ; <$D3=demo sounds
C275: B7 40 51    STA    $4051                  ; SOUND: super pellet eaten
C278: CC C3 56    LDD    #$C356                 ; [function_address] ; -> attract_super_pacman_state_c356
C27B: FD 16 30    STD    pacman_object_1630
C27E: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C281: ED 44       STD    $4,U
C283: 39          RTS
C284: BD F4 FC    JSR    power_pellet_blink_f4fc
C287: BD F6 AC    JSR    collision_with_pacman_f6ac
C28A: 25 01       BCS    $C28D
C28C: 39          RTS
C28D: 96 D3       LDA    <$D3                   ; <$D3=demo sounds
C28F: B7 40 4A    STA    $404A                  ; SOUND: fruit eaten
C292: CC C3 1F    LDD    #$C31F                 ; [function_address] ; -> attract_pacman_eaten_state_c31f
C295: FD 16 30    STD    pacman_object_1630
C298: CC C3 F0    LDD    #$C3F0                 ; [function_address] ; -> attract_ghost_chase_c3f0
C29B: BD F7 7D    JSR    set_ghosts_state_f77d
C29E: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C2A1: ED 44       STD    $4,U
C2A3: 39          RTS

attract_init_pacman_c2a4:
C2A4: 7F 16 26    CLR    $1626
C2A7: 8E 00 48    LDX    #$0048
C2AA: CC 01 03    LDD    #$0103
C2AD: BD F5 1E    JSR    pacman_object_setup_f51e
C2B0: CC 00 C0    LDD    #$00C0
C2B3: ED 50       STD    -$10,U
C2B5: 8E C2 BB    LDX    #$C2BB                 ; [function_address] ; -> attract_pacman_task_c2bb
C2B8: AF C4       STX    ,U
C2BA: 39          RTS

attract_pacman_task_c2bb:
C2BB: BD C3 0A    JSR    object_move_by_speed_c30a
C2BE: BD F5 FA    JSR    pacman_anim_frame_f5fa
C2C1: A6 4C       LDA    $C,U
C2C3: 81 F8       CMPA   #$F8
C2C5: 24 01       BCC    $C2C8
C2C7: 39          RTS
C2C8: 8E F8 68    LDX    #$F868                 ; NOT a function address: coordinates y=$F8 x=$68
C2CB: CC 01 01    LDD    #$0101
C2CE: BD F5 1E    JSR    pacman_object_setup_f51e
C2D1: CC 00 40    LDD    #$0040
C2D4: BD E2 BB    JSR    task_wait_init_e2bb
C2D7: BD E2 C4    JSR    task_wait_e2c4
C2DA: BD C3 0A    JSR    object_move_by_speed_c30a
C2DD: BD F5 FA    JSR    pacman_anim_frame_f5fa
C2E0: A6 4C       LDA    $C,U
C2E2: 81 08       CMPA   #$08
C2E4: 25 01       BCS    $C2E7
C2E6: 39          RTS
C2E7: 8E 00 94    LDX    #$0094
C2EA: CC 01 03    LDD    #$0103
C2ED: BD F5 1E    JSR    pacman_object_setup_f51e
C2F0: CC 00 40    LDD    #$0040
C2F3: BD E2 BB    JSR    task_wait_init_e2bb
C2F6: BD E2 C4    JSR    task_wait_e2c4
C2F9: 10 8E 00 94 LDY    #$0094
C2FD: BD C3 A4    JSR    attract_init_ghosts_c3a4
C300: BD E2 B4    JSR    task_yield_e2b4
C303: BD C3 0A    JSR    object_move_by_speed_c30a
C306: BD F5 FA    JSR    pacman_anim_frame_f5fa
C309: 39          RTS

;----------------------------------------------------------------------------
; Move the object U by its speed: 16-bit accumulator $E,U += speed -$10,U;
; the integer part = number of 1-pixel steps (object_step_one_pixel_fa48).
;----------------------------------------------------------------------------
object_move_by_speed_c30a:
C30A: AE 4E       LDX    $E,U
C30C: EC 50       LDD    -$10,U
C30E: 30 8B       LEAX   D,X
C310: AF 4E       STX    $E,U
C312: A6 4E       LDA    $E,U
C314: 26 01       BNE    $C317
C316: 39          RTS
C317: BD FA 48    JSR    object_step_one_pixel_fa48
C31A: 6A 4E       DEC    $E,U
C31C: 26 F9       BNE    $C317
C31E: 39          RTS

attract_pacman_eaten_state_c31f:
C31F: AE 4C       LDX    $C,U
C321: CC 01 01    LDD    #$0101
C324: BD F5 1E    JSR    pacman_object_setup_f51e
C327: CC 00 3C    LDD    #$003C
C32A: BD E2 BB    JSR    task_wait_init_e2bb
C32D: BD E2 C4    JSR    task_wait_e2c4
C330: BD C3 0A    JSR    object_move_by_speed_c30a
C333: BD F5 FA    JSR    pacman_anim_frame_f5fa
C336: A6 4C       LDA    $C,U
C338: 81 08       CMPA   #$08
C33A: 25 01       BCS    $C33D
C33C: 39          RTS
C33D: 8E 00 BC    LDX    #$00BC
C340: CC 01 03    LDD    #$0103
C343: BD F5 1E    JSR    pacman_object_setup_f51e
C346: 10 8E 00 BC LDY    #$00BC
C34A: BD C3 A4    JSR    attract_init_ghosts_c3a4
C34D: BD E2 B4    JSR    task_yield_e2b4
C350: BD C3 0A    JSR    object_move_by_speed_c30a
C353: 7E F5 FA    JMP    pacman_anim_frame_f5fa

attract_super_pacman_state_c356:
C356: 86 01       LDA    #$01
C358: A7 56       STA    -$A,U
C35A: AE 4C       LDX    $C,U
C35C: CC 01 01    LDD    #$0101
C35F: BD F5 1E    JSR    pacman_object_setup_f51e
C362: CC 01 80    LDD    #$0180
C365: ED 50       STD    -$10,U
C367: BD F5 FA    JSR    pacman_anim_frame_f5fa
C36A: BD E2 B4    JSR    task_yield_e2b4
C36D: CC E2 BA    LDD    #$e2ba                 ; [function_address] ; -> task_nop_rts_e2ba
C370: BD F7 8D    JSR    set_ghosts_runner_f78d
C373: CC 00 3C    LDD    #$003C
C376: BD E2 BB    JSR    task_wait_init_e2bb
C379: BD E2 C4    JSR    task_wait_e2c4
C37C: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
C37F: BD F7 8D    JSR    set_ghosts_runner_f78d
C382: BD E2 B4    JSR    task_yield_e2b4
C385: BD C3 0A    JSR    object_move_by_speed_c30a
C388: BD F5 FA    JSR    pacman_anim_frame_f5fa
C38B: A6 4C       LDA    $C,U
C38D: 81 08       CMPA   #$08
C38F: 25 01       BCS    $C392
C391: 39          RTS
C392: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C395: ED 44       STD    $4,U
C397: A6 4C       LDA    $C,U
C399: 81 F9       CMPA   #$F9
C39B: 24 01       BCC    $C39E
C39D: 39          RTS
C39E: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C3A1: ED 44       STD    $4,U
C3A3: 39          RTS

attract_init_ghosts_c3a4:
C3A4: CE 0E 90    LDU    #$0E90
C3A7: C6 03       LDB    #$03
C3A9: E7 56       STB    -$A,U
C3AB: 58          ASLB
C3AC: 8E C3 D2    LDX    #$C3D2
C3AF: EC 85       LDD    B,X
C3B1: ED 42       STD    $2,U
C3B3: 10 AF 4C    STY    $C,U
C3B6: CC 00 E0    LDD    #$00E0
C3B9: ED 50       STD    -$10,U
C3BB: 86 03       LDA    #$03
C3BD: A7 53       STA    -$D,U
C3BF: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
C3C2: ED 44       STD    $4,U
C3C4: CC C3 DA    LDD    #$C3DA                 ; [function_address] ; -> attract_ghost_task_c3da
C3C7: ED C4       STD    ,U
C3C9: E6 56       LDB    -$A,U
C3CB: 33 C8 20    LEAU   $20,U
C3CE: 5A          DECB
C3CF: 2A D8       BPL    $C3A9
C3D1: 39          RTS

attract_ghost_task_c3da:
C3DA: BD E2 C4    JSR    task_wait_e2c4
C3DD: BD C3 0A    JSR    object_move_by_speed_c30a
C3E0: BD F8 47    JSR    ghost_anim_frame_f847
C3E3: A6 4C       LDA    $C,U
C3E5: 81 F9       CMPA   #$F9
C3E7: 24 01       BCC    $C3EA
C3E9: 39          RTS
C3EA: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C3ED: ED 44       STD    $4,U
C3EF: 39          RTS

attract_ghost_chase_c3f0:
C3F0: 86 01       LDA    #$01
C3F2: A7 53       STA    -$D,U
C3F4: CC 00 40    LDD    #$0040
C3F7: ED 50       STD    -$10,U
C3F9: BD F8 CA    JSR    ghost_eyes_frame_f8ca
C3FC: CC 00 3C    LDD    #$003C
C3FF: BD E2 BB    JSR    task_wait_init_e2bb
C402: BD E2 C4    JSR    task_wait_e2c4
C405: BD C3 0A    JSR    object_move_by_speed_c30a
C408: BD F8 CA    JSR    ghost_eyes_frame_f8ca
C40B: BD F6 AC    JSR    collision_with_pacman_f6ac
C40E: 25 01       BCS    $C411
C410: 39          RTS
C411: 96 D3       LDA    <$D3                   ; <$D3=demo sounds
C413: B7 40 4D    STA    $404D                  ; SOUND: ghost eaten
C416: CC F1 01    LDD    #$f101                 ; [function_address] ; -> runner_draw_sprite_f101
C419: BD F7 8A    JSR    set_pacman_runner_f78a
C41C: CC F0 EF    LDD    #$F0EF                 ; [function_address] ; -> runner_hide_sprite_f0ef
C41F: ED 44       STD    $4,U
C421: CC 34 3C    LDD    #$343C
C424: AB 56       ADDA   -$A,U
C426: CE 16 30    LDU    #$1630
C429: 6F 49       CLR    $9,U
C42B: ED 4A       STD    $A,U
C42D: CC 00 1E    LDD    #$001E
C430: BD E2 BB    JSR    task_wait_init_e2bb
C433: BD E2 C4    JSR    task_wait_e2c4
C436: 86 01       LDA    #$01
C438: B7 16 3B    STA    $163B
C43B: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
C43E: BD F7 8A    JSR    set_pacman_runner_f78a
C441: BD E2 B4    JSR    task_yield_e2b4
C444: 39          RTS

;----------------------------------------------------------------------------
; DEMO GAME: clears the demo recording area, level init, input mode 2 (demo
; playback from the table at $C58C, see irq_input_handler_c537), starts
; Pac-Man and the ghosts and loops until all items are eaten.
;----------------------------------------------------------------------------
demo_game_c445:
C445: 4F          CLRA
C446: CE 12 00    LDU    #$1200
C449: 8E 02 00    LDX    #$0200
C44C: BD EE B1    JSR    fill_words_eeb1
C44F: 97 B6       STA    <$B6

demo_game_restart_c451:
C451: CC 00 00    LDD    #$0000
C454: DD EC       STD    <$EC                   ; <$EC=random seed
C456: 97 84       STA    <$84                   ; <$84=current player (0/1)
C458: CE 10 03    LDU    #$1003
C45B: A7 C0       STA    ,U+
C45D: 8E 00 1E    LDX    #$001E
C460: BD EE B1    JSR    fill_words_eeb1
C463: CE 10 43    LDU    #$1043
C466: 8E 00 1E    LDX    #$001E
C469: BD EE B1    JSR    fill_words_eeb1
C46C: BD C5 14    JSR    init_level_params_demo_c514
C46F: 86 03       LDA    #$03
C471: 97 14       STA    <$14                   ; <$14=maze colour
C473: BD E2 9E    JSR    enable_object_tasks_e29e
C476: BD E2 B4    JSR    task_yield_e2b4
C479: BD EA 33    JSR    init_maze_objects_ea33
C47C: BD EB 0C    JSR    print_game_over_text_eb0c
C47F: CC 00 00    LDD    #$0000
C482: DD 92       STD    <$92                   ; <$92=frames since level start
C484: DD C2       STD    <$C2                   ; <$C2=controls read by the I/O chip
C486: 97 AC       STA    <$AC                   ; <$AC=current controls (active high)
C488: 8E 12 00    LDX    #$1200
C48B: 8E C5 8C    LDX    #$C58C
C48E: BD C5 58    JSR    demo_set_pointer_c558
C491: 96 B6       LDA    <$B6
C493: 4C          INCA
C494: 86 02       LDA    #$02
C496: 97 AB       STA    <$AB                   ; <$AB=input mode 0=live 1=record 2=demo playback
C498: BD F5 08    JSR    pacman_start_f508
C49B: BD F7 70    JSR    ghosts_start_f770
C49E: BD E2 B4    JSR    task_yield_e2b4
C4A1: DC 92       LDD    <$92                   ; <$92=frames since level start
C4A3: C3 00 01    ADDD   #$0001
C4A6: 25 02       BCS    $C4AA
C4A8: DD 92       STD    <$92                   ; <$92=frames since level start
C4AA: 96 90       LDA    <$90                   ; <$90=fruits left
C4AC: 9B 91       ADDA   <$91                   ; <$91=power pellets left
C4AE: 27 01       BEQ    demo_game_end_c4b1
C4B0: 39          RTS

demo_game_end_c4b1:
C4B1: 0F AB       CLR    <$AB                   ; <$AB=input mode 0=live 1=record 2=demo playback
C4B3: CC 00 3C    LDD    #$003C
C4B6: BD E2 BB    JSR    task_wait_init_e2bb
C4B9: BD E2 C4    JSR    task_wait_e2c4
C4BC: 7E C0 03    JMP    attract_loop_c003

;----------------------------------------------------------------------------
; Not referenced in this listing (maybe an entry of the initial task table at $E288). Redraws a 5x32 block from $1200.
;----------------------------------------------------------------------------
function_c4bf:
C4BF: 96 B6       LDA    <$B6
C4C1: 26 03       BNE    $C4C6
C4C3: 4C          INCA
C4C4: 97 B6       STA    <$B6
C4C6: BD E2 9E    JSR    enable_object_tasks_e29e
C4C9: BD E2 B4    JSR    task_yield_e2b4
C4CC: 86 20       LDA    #$20
C4CE: CE 00 00    LDU    #$0000
C4D1: 8E 02 00    LDX    #$0200
C4D4: BD EE B1    JSR    fill_words_eeb1
C4D7: 86 04       LDA    #$04
C4D9: 8E 02 00    LDX    #$0200
C4DC: BD EE B1    JSR    fill_words_eeb1
C4DF: 8E 12 00    LDX    #$1200
C4E2: CE 03 A0    LDU    #$03A0
C4E5: 86 05       LDA    #$05
C4E7: C6 20       LDB    #$20
C4E9: 34 06       PSHS   D
C4EB: 10 8E 00 02 LDY    #$0002
C4EF: BD FE 1C    JSR    print_bcd_fe1c
C4F2: 35 06       PULS   D
C4F4: 33 C9 00 81 LEAU   $0081,U
C4F8: 5A          DECB
C4F9: 26 EE       BNE    $C4E9
C4FB: 33 C9 FF 20 LEAU   -$00E0,U
C4FF: 4A          DECA
C500: 26 E5       BNE    $C4E7
C502: BD E2 B4    JSR    task_yield_e2b4
C505: 96 AC       LDA    <$AC                   ; <$AC=current controls (active high)
C507: 85 80       BITA   #$80
C509: 10 26 FF 38 LBNE   demo_game_c445
C50D: 85 20       BITA   #$20
C50F: 10 26 FF 3E LBNE   demo_game_restart_c451
C513: 39          RTS

init_level_params_demo_c514:
C514: 8E C5 21    LDX    #$C521
C517: CE 10 94    LDU    #$1094
C51A: 10 8E 00 0B LDY    #$000B
C51E: 7E EE BA    JMP    memcpy_eeba

;----------------------------------------------------------------------------
; Called by the IRQ every frame: controls -> $10AC.
;  <$AB = 0 : live controls ($10C2)
;  <$AB = 1 : RECORD mode (development): stores (controls, frames) pairs
;  <$AB = 2 : DEMO playback from (<$AE). Also checks that the copyright
;             text at $C112 still reads 'NAMCO ' (anti-tampering).
;----------------------------------------------------------------------------
irq_input_handler_c537:
C537: 96 AB       LDA    <$AB                   ; <$AB=input mode 0=live 1=record 2=demo playback
C539: 26 05       BNE    $C540
C53B: 96 C2       LDA    <$C2                   ; <$C2=controls read by the I/O chip
C53D: 97 AC       STA    <$AC                   ; <$AC=current controls (active high)
C53F: 39          RTS
C540: 4A          DECA
C541: 26 1A       BNE    $C55D
C543: 0C AD       INC    <$AD                   ; <$AD=demo recording frame count
C545: 96 C2       LDA    <$C2                   ; <$C2=controls read by the I/O chip
C547: 97 AC       STA    <$AC                   ; <$AC=current controls (active high)
C549: 98 C3       EORA   <$C3                   ; <$C3=previous controls
C54B: 84 2F       ANDA   #$2F
C54D: 26 01       BNE    $C550
C54F: 39          RTS
C550: 9E AE       LDX    <$AE                   ; <$AE=demo data pointer
C552: 96 C3       LDA    <$C3                   ; <$C3=previous controls
C554: D6 AD       LDB    <$AD                   ; <$AD=demo recording frame count
C556: ED 81       STD    ,X++

demo_set_pointer_c558:
C558: 9F AE       STX    <$AE                   ; <$AE=demo data pointer
C55A: 0F AD       CLR    <$AD                   ; <$AD=demo recording frame count
C55C: 39          RTS
C55D: FC C1 12    LDD    $C112
C560: 83 4E 41    SUBD   #$4E41
C563: 26 1D       BNE    $C582
C565: FC C1 14    LDD    $C114
C568: 83 4D 43    SUBD   #$4D43
C56B: 26 15       BNE    $C582
C56D: FC C1 16    LDD    $C116
C570: 83 4F 20    SUBD   #$4F20
C573: 26 0D       BNE    $C582
C575: 9E AE       LDX    <$AE                   ; <$AE=demo data pointer
C577: 0C AD       INC    <$AD                   ; <$AD=demo recording frame count
C579: EC 81       LDD    ,X++
C57B: 97 AC       STA    <$AC                   ; <$AC=current controls (active high)
C57D: D1 AD       CMPB   <$AD                   ; <$AD=demo recording frame count
C57F: 27 D7       BEQ    demo_set_pointer_c558
C581: 39          RTS
C582: 0F 8B       CLR    <$8B                   ; <$8B=game sounds enabled (0 in attract)
C584: 96 C2       LDA    <$C2                   ; <$C2=controls read by the I/O chip
C586: 2A ED       BPL    $C575
C588: 0C 8B       INC    <$8B                   ; <$8B=game sounds enabled (0 in attract)
C58A: 20 AF       BRA    $C53B

;----------------------------------------------------------------------------
; DEVELOPMENT MONITOR (leftover): memory viewer/editor using a keypad read
; at $A0FE.. (not present on the production board). Not needed for a port.
;----------------------------------------------------------------------------
debug_monitor_c63e:
C63E: BD C7 28    JSR    debug_cursor_wrap_c728
C641: 8D 4E       BSR    debug_monitor_keys_c691
C643: CE 00 E0    LDU    #$00E0
C646: 8E 10 F0    LDX    #$10F0
C649: 10 8E FF E0 LDY    #$FFE0
C64D: C6 03       LDB    #$03
C64F: A6 84       LDA    ,X
C651: 8D 25       BSR    hex_digit_high_c678
C653: 8D 33       BSR    debug_put_char_c688
C655: A6 80       LDA    ,X+
C657: 8D 23       BSR    hex_digit_low_c67c
C659: 8D 2D       BSR    debug_put_char_c688
C65B: 5A          DECB
C65C: 26 F1       BNE    $C64F
C65E: CE 04 E0    LDU    #$04E0
C661: D6 F3       LDB    <$F3
C663: 8D 08       BSR    debug_fill_c66d
C665: 86 11       LDA    #$11
C667: 8D 1F       BSR    debug_put_char_c688
C669: C6 05       LDB    #$05
C66B: D0 F3       SUBB   <$F3

debug_fill_c66d:
C66D: 26 01       BNE    $C670
C66F: 39          RTS
C670: 86 10       LDA    #$10
C672: 8D 14       BSR    debug_put_char_c688
C674: 5A          DECB
C675: 26 FB       BNE    $C672
C677: 39          RTS

hex_digit_high_c678:
C678: 44          LSRA
C679: 44          LSRA
C67A: 44          LSRA
C67B: 44          LSRA

hex_digit_low_c67c:
C67C: 84 0F       ANDA   #$0F
C67E: 8B 30       ADDA   #$30
C680: 81 3A       CMPA   #$3A
C682: 24 01       BCC    $C685
C684: 39          RTS
C685: 8B 07       ADDA   #$07
C687: 39          RTS

debug_put_char_c688:
C688: A7 C4       STA    ,U
C68A: 1E 20       EXG    Y,D
C68C: 33 CB       LEAU   D,U
C68E: 1E 20       EXG    Y,D
C690: 39          RTS

debug_monitor_keys_c691:
C691: 8D 18       BSR    debug_read_keypad_c6ab
C693: 91 F5       CMPA   <$F5
C695: 26 0D       BNE    $C6A4
C697: 81 FF       CMPA   #$FF
C699: 27 09       BEQ    $C6A4
C69B: D6 F6       LDB    <$F6
C69D: D1 F7       CMPB   <$F7
C69F: 26 03       BNE    $C6A4
C6A1: 5C          INCB
C6A2: 27 36       BEQ    $C6DA
C6A4: A6 9F 10 F0 LDA    [$10F0]
C6A8: 97 F2       STA    <$F2
C6AA: 39          RTS

debug_read_keypad_c6ab:
C6AB: DC F5       LDD    <$F5
C6AD: DD F6       STD    <$F6
C6AF: 96 F4       LDA    <$F4
C6B1: 97 F5       STA    <$F5
C6B3: 8E A0 FE    LDX    #$A0FE
C6B6: 86 10       LDA    #$10
C6B8: E6 84       LDB    ,X
C6BA: E6 84       LDB    ,X
C6BC: 53          COMB
C6BD: C4 0F       ANDB   #$0F
C6BF: 26 13       BNE    $C6D4
C6C1: 34 06       PSHS   D
C6C3: 1F 10       TFR    X,D
C6C5: 58          ASLB
C6C6: 5C          INCB
C6C7: 1F 01       TFR    D,X
C6C9: 35 06       PULS   D
C6CB: 80 04       SUBA   #$04
C6CD: 24 E9       BCC    $C6B8
C6CF: 86 FF       LDA    #$FF
C6D1: 97 F4       STA    <$F4
C6D3: 39          RTS
C6D4: 54          LSRB
C6D5: 25 FA       BCS    $C6D1
C6D7: 4C          INCA
C6D8: 20 FA       BRA    $C6D4
C6DA: 81 10       CMPA   #$10
C6DC: 25 2C       BCS    debug_enter_nibble_c70a
C6DE: 27 42       BEQ    debug_cursor_right_c722
C6E0: 81 12       CMPA   #$12
C6E2: 25 42       BCS    debug_cursor_left_c726
C6E4: 34 01       PSHS   CC
C6E6: D6 F3       LDB    <$F3
C6E8: C1 04       CMPB   #$04
C6EA: 25 02       BCS    $C6EE
C6EC: C6 03       LDB    #$03
C6EE: 8E C7 02    LDX    #$C702
C6F1: 3A          ABX
C6F2: EC 85       LDD    B,X
C6F4: 35 01       PULS   CC
C6F6: 26 05       BNE    $C6FD
C6F8: 43          COMA
C6F9: 53          COMB
C6FA: C3 00 01    ADDD   #$0001
C6FD: D3 F0       ADDD   <$F0
C6FF: DD F0       STD    <$F0
C701: 39          RTS

debug_enter_nibble_c70a:
C70A: 8D 2D       BSR    debug_store_nibble_c739
C70C: 0C F3       INC    <$F3
C70E: 96 F3       LDA    <$F3
C710: 81 05       CMPA   #$05
C712: 24 01       BCC    $C715
C714: 39          RTS
C715: 27 04       BEQ    $C71B
C717: 0A F3       DEC    <$F3
C719: 0A F3       DEC    <$F3
C71B: 96 F2       LDA    <$F2
C71D: A7 9F 10 F0 STA    [$10F0]
C721: 39          RTS

debug_cursor_right_c722:
C722: 0C F3       INC    <$F3
C724: 20 02       BRA    debug_cursor_wrap_c728

debug_cursor_left_c726:
C726: 0A F3       DEC    <$F3

debug_cursor_wrap_c728:
C728: 96 F3       LDA    <$F3
C72A: 2A 05       BPL    $C731
C72C: 86 05       LDA    #$05
C72E: 97 F3       STA    <$F3
C730: 39          RTS
C731: 81 06       CMPA   #$06
C733: 24 01       BCC    $C736
C735: 39          RTS
C736: 0F F3       CLR    <$F3
C738: 39          RTS

debug_store_nibble_c739:
C739: 8E 10 F0    LDX    #$10F0
C73C: D6 F3       LDB    <$F3
C73E: 54          LSRB
C73F: 3A          ABX
C740: 25 0F       BCS    $C751
C742: 48          ASLA
C743: 48          ASLA
C744: 48          ASLA
C745: 48          ASLA
C746: 97 F4       STA    <$F4
C748: A6 84       LDA    ,X
C74A: 84 0F       ANDA   #$0F
C74C: 9A F4       ORA    <$F4
C74E: A7 84       STA    ,X
C750: 39          RTS
C751: A6 84       LDA    ,X
C753: 84 F0       ANDA   #$F0
C755: 9A F4       ORA    <$F4
C757: A7 84       STA    ,X
C759: 39          RTS

;----------------------------------------------------------------------------
; Intermission (cut-scene) check after a level: intermission_select_c7b2
; decides from the level (<$18/<$19, table $C7D8) which cut-scene (1-5, <$AA)
; to play. If one: intermission_run_c762 POPS ITS RETURN ADDRESS into $10E4,
; plays the scene over several frames (task waits), then JMP [$10E4].
;----------------------------------------------------------------------------
intermission_check_c75a:
C75A: BD C7 B2    JSR    intermission_select_c7b2
C75D: D6 AA       LDB    <$AA                   ; <$AA=intermission number (0 = none)
C75F: 26 01       BNE    intermission_run_c762
C761: 39          RTS

;----------------------------------------------------------------------------
; (was 'set_10e4_return_address_c762') Runs a cut-scene: return address
; saved in $10E4 (the task can yield many frames in between), sound $4055,
; starts the 2 actor groups (tables $C796 / $C7A8), waits $258 frames.
; The check of $E28A (must be $E3E6) is an anti-tampering test: if it
; fails the task never continues.
;----------------------------------------------------------------------------
intermission_run_c762:
C762: 35 10       PULS   X
C764: 9F E4       STX    <$E4                   ; <$E4=saved return address
C766: 86 01       LDA    #$01
C768: B7 40 55    STA    $4055                  ; SOUND: intermission music
C76B: BD EE 06    JSR    clear_screen_and_status_ee06
C76E: 8D 1E       BSR    intermission_start_actor1_c78e
C770: 8D 2E       BSR    intermission_start_actor2_c7a0
C772: CC 02 58    LDD    #$0258
C775: BD E2 BB    JSR    task_wait_init_e2bb
C778: BD E2 C4    JSR    task_wait_e2c4
C77B: BD E2 9E    JSR    enable_object_tasks_e29e
C77E: BD E2 B4    JSR    task_yield_e2b4
; another rom tampering check
C781: FC E2 8A    LDD    $E28A
C784: 83 E3 E6    SUBD   #$E3E6
C787: 27 01       BEQ    $C78A
C789: 39          RTS
; called at the end of intermission, probably a protection
; jumps at E88D
C78A: 6E 9F 10 E4 JMP    [$10E4]                ; return to the saved caller

; ghost state machine variant A

;----------------------------------------------------------------------------
; Start cut-scene actor group 1 (Pac-Man side) for cut-scene <$AA (1-5).
;----------------------------------------------------------------------------
intermission_start_actor1_c78e:
C78E: D6 AA       LDB    <$AA                   ; <$AA=intermission number (0 = none)
C790: 58          ASLB
C791: 8E C7 94    LDX    #intermission_actor1_table_c796-2
C794: 6E 95       JMP    [B,X]                  ; [indirect_jump] [nb_entries=5]

intermission_actor1_table_c796:
	dc.w	im1_pacman_init_c7e3
	dc.w	im2_pacman_init_c8b7
	dc.w	im3_pacman_init_c961
	dc.w	im4_init_ca64
	dc.w	im5_pacman_init_cb39

; ghost state machine, variant B

;----------------------------------------------------------------------------
; Start cut-scene actor group 2 (ghosts) for cut-scene <$AA (1-5).
;----------------------------------------------------------------------------
intermission_start_actor2_c7a0:
C7A0: D6 AA       LDB    <$AA                   ; <$AA=intermission number (0 = none)
C7A2: 58          ASLB
C7A3: 8E C7 A6    LDX    #intermission_actor2_table_c7a8-2
C7A6: 6E 95       JMP    [B,X]                  ; [indirect_jump] [nb_entries=5]

intermission_actor2_table_c7a8:
	dc.w	im1_ghosts_init_c84c
	dc.w	im2_ghost_init_c907
	dc.w	im3_ghost_init_c9ff
	dc.w	im4_ghosts_init_caa9
	dc.w	im5_ghosts_init_cb79

;----------------------------------------------------------------------------
; Choose the cut-scene number from the level (table $C7D8: [levels to wait, scene]).
;----------------------------------------------------------------------------
intermission_select_c7b2:
C7B2: 0F AA       CLR    <$AA                   ; <$AA=intermission number (0 = none)
C7B4: D6 18       LDB    <$18                   ; <$18=intermission schedule index
C7B6: 58          ASLB
C7B7: 8E C7 D8    LDX    #$C7D8
C7BA: 3A          ABX
C7BB: A6 84       LDA    ,X
C7BD: 26 01       BNE    $C7C0
C7BF: 39          RTS
C7C0: 2A 06       BPL    $C7C8
C7C2: 84 7F       ANDA   #$7F
C7C4: 97 18       STA    <$18                   ; <$18=intermission schedule index
C7C6: 20 EC       BRA    $C7B4
C7C8: 0C 19       INC    <$19                   ; <$19=intermission counter
C7CA: 90 19       SUBA   <$19                   ; <$19=intermission counter
C7CC: 27 01       BEQ    $C7CF
C7CE: 39          RTS
C7CF: 97 19       STA    <$19                   ; <$19=intermission counter
C7D1: 0C 18       INC    <$18                   ; <$18=intermission schedule index
C7D3: E6 01       LDB    $1,X
C7D5: D7 AA       STB    <$AA                   ; <$AA=intermission number (0 = none)
C7D7: 39          RTS

im1_pacman_init_c7e3:
C7E3: 7F 16 26    CLR    $1626
C7E6: 8E F8 80    LDX    #$F880
C7E9: CC 01 01    LDD    #$0101
C7EC: BD F5 1E    JSR    pacman_object_setup_f51e
C7EF: CC 00 C0    LDD    #$00C0
C7F2: ED 50       STD    -$10,U
C7F4: 8E C7 FA    LDX    #$C7FA                 ; [function_address] ; -> im1_pacman_task_c7fa
C7F7: AF C4       STX    ,U
C7F9: 39          RTS

im1_pacman_task_c7fa:
C7FA: BD C3 0A    JSR    object_move_by_speed_c30a
C7FD: BD F5 FA    JSR    pacman_anim_frame_f5fa
C800: A6 4C       LDA    $C,U
C802: 81 08       CMPA   #$08
C804: 25 01       BCS    $C807
C806: 39          RTS
C807: CC F1 01    LDD    #$f101                 ; [function_address] ; -> runner_draw_sprite_f101
C80A: BD F7 8D    JSR    set_ghosts_runner_f78d
C80D: CC 00 3C    LDD    #$003C
C810: BD E2 BB    JSR    task_wait_init_e2bb
C813: BD E2 C4    JSR    task_wait_e2c4
C816: 86 01       LDA    #$01
C818: A7 56       STA    -$A,U
C81A: 8E 00 40    LDX    #$0040
C81D: CC 01 03    LDD    #$0103
C820: BD F5 1E    JSR    pacman_object_setup_f51e
C823: CC 0C 14    LDD    #$0C14
C826: ED 49       STD    $9,U
C828: CC 01 80    LDD    #$0180
C82B: ED 50       STD    -$10,U
C82D: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
C830: BD F7 8D    JSR    set_ghosts_runner_f78d
C833: CC C8 90    LDD    #$C890                 ; [function_address] ; -> im1_super_pacman_task_c890
C836: BD F7 7D    JSR    set_ghosts_state_f77d
C839: BD E2 B4    JSR    task_yield_e2b4
C83C: BD C3 0A    JSR    object_move_by_speed_c30a
C83F: A6 4C       LDA    $C,U
C841: 81 F8       CMPA   #$F8
C843: 24 01       BCC    $C846
C845: 39          RTS
C846: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C849: ED 44       STD    $4,U
C84B: 39          RTS

im1_ghosts_init_c84c:
C84C: 10 8E F8 80 LDY    #$F880
C850: CE 0E 90    LDU    #$0E90
C853: C6 03       LDB    #$03
C855: E7 56       STB    -$A,U
C857: 58          ASLB
C858: 8E C8 7E    LDX    #$C87E
C85B: EC 85       LDD    B,X
C85D: ED 42       STD    $2,U
C85F: 10 AF 4C    STY    $C,U
C862: CC 00 C0    LDD    #$00C0
C865: ED 50       STD    -$10,U
C867: 86 01       LDA    #$01
C869: A7 53       STA    -$D,U
C86B: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
C86E: ED 44       STD    $4,U
C870: CC C8 86    LDD    #$C886                 ; [function_address] ; -> im_ghost_follow_task_c886
C873: ED C4       STD    ,U
C875: E6 56       LDB    -$A,U
C877: 33 C8 20    LEAU   $20,U
C87A: 5A          DECB
C87B: 2A D8       BPL    $C855
C87D: 39          RTS

im_ghost_follow_task_c886:
C886: BD E2 C4    JSR    task_wait_e2c4
C889: BD C3 0A    JSR    object_move_by_speed_c30a
C88C: BD F8 47    JSR    ghost_anim_frame_f847
C88F: 39          RTS

im1_super_pacman_task_c890:
C890: CC 00 9F    LDD    #$009F
C893: BD E2 BB    JSR    task_wait_init_e2bb
C896: BD C8 9D    JSR    im1_set_size_c89d
C899: BD E2 C4    JSR    task_wait_e2c4
C89C: 39          RTS

im1_set_size_c89d:
C89D: E6 43       LDB    $3,U
C89F: C4 E0       ANDB   #$E0
C8A1: 54          LSRB
C8A2: 54          LSRB
C8A3: 54          LSRB
C8A4: 54          LSRB
C8A5: 8E C8 AD    LDX    #$C8AD
C8A8: EC 85       LDD    B,X
C8AA: ED 49       STD    $9,U
C8AC: 39          RTS

im2_pacman_init_c8b7:
C8B7: 86 01       LDA    #$01
C8B9: B7 16 26    STA    $1626
C8BC: 8E 00 80    LDX    #$0080
C8BF: CC 01 01    LDD    #$0101
C8C2: BD F5 1E    JSR    pacman_object_setup_f51e
C8C5: CC 01 00    LDD    #$0100
C8C8: ED 50       STD    -$10,U
C8CA: 8E C8 D0    LDX    #$C8D0                 ; [function_address] ; -> im2_pacman_task_c8d0
C8CD: AF C4       STX    ,U
C8CF: 39          RTS

im2_pacman_task_c8d0:
C8D0: CC 00 30    LDD    #$0030
C8D3: BD E2 BB    JSR    task_wait_init_e2bb
C8D6: BD E2 C4    JSR    task_wait_e2c4
C8D9: BD C3 0A    JSR    object_move_by_speed_c30a
C8DC: BD F5 FA    JSR    pacman_anim_frame_f5fa
C8DF: A6 4C       LDA    $C,U
C8E1: 81 08       CMPA   #$08
C8E3: 25 01       BCS    $C8E6
C8E5: 39          RTS
C8E6: 6F 56       CLR    -$A,U
C8E8: 8E 00 80    LDX    #$0080
C8EB: CC 01 03    LDD    #$0103
C8EE: BD F5 1E    JSR    pacman_object_setup_f51e
C8F1: BD E2 B4    JSR    task_yield_e2b4
C8F4: BD C3 0A    JSR    object_move_by_speed_c30a
C8F7: BD F5 FA    JSR    pacman_anim_frame_f5fa
C8FA: A6 4C       LDA    $C,U
C8FC: 81 F8       CMPA   #$F8
C8FE: 24 01       BCC    $C901
C900: 39          RTS
C901: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C904: ED 44       STD    $4,U
C906: 39          RTS

im2_ghost_init_c907:
C907: CE 0E 90    LDU    #$0E90
C90A: CC FF 80    LDD    #$FF80
C90D: ED 4C       STD    $C,U
C90F: CC 01 00    LDD    #$0100
C912: ED 50       STD    -$10,U
C914: 86 01       LDA    #$01
C916: A7 53       STA    -$D,U
C918: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
C91B: ED 44       STD    $4,U
C91D: CC C9 23    LDD    #$C923                 ; [function_address] ; -> im2_ghost_task_c923
C920: ED C4       STD    ,U
C922: 39          RTS

im2_ghost_task_c923:
C923: BD C3 0A    JSR    object_move_by_speed_c30a
C926: BD F8 CA    JSR    ghost_eyes_frame_f8ca
C929: A6 4C       LDA    $C,U
C92B: 81 08       CMPA   #$08
C92D: 25 01       BCS    $C930
C92F: 39          RTS
C930: CC 00 60    LDD    #$0060
C933: BD E2 BB    JSR    task_wait_init_e2bb
C936: BD E2 C4    JSR    task_wait_e2c4
C939: 86 03       LDA    #$03
C93B: A7 53       STA    -$D,U
C93D: CC 0C 04    LDD    #$0C04
C940: A7 49       STA    $9,U
C942: E7 4B       STB    $B,U
C944: BD E2 B4    JSR    task_yield_e2b4
C947: BD C3 0A    JSR    object_move_by_speed_c30a
C94A: 96 81       LDA    <$81                   ; <$81=frame counter
C94C: 44          LSRA
C94D: 44          LSRA
C94E: 84 01       ANDA   #$01
C950: 8B 6B       ADDA   #$6B
C952: A7 4A       STA    $A,U
C954: A6 4C       LDA    $C,U
C956: 81 F8       CMPA   #$F8
C958: 24 01       BCC    $C95B
C95A: 39          RTS
C95B: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C95E: ED 44       STD    $4,U
C960: 39          RTS

im3_pacman_init_c961:
C961: 7F 16 26    CLR    $1626
C964: 8E 00 80    LDX    #$0080
C967: CC 01 03    LDD    #$0103
C96A: BD F5 1E    JSR    pacman_object_setup_f51e
C96D: CC 01 00    LDD    #$0100
C970: ED 50       STD    -$10,U
C972: 8E C9 78    LDX    #$C978                 ; [function_address] ; -> im3_pacman_task_c978
C975: AF C4       STX    ,U
C977: 39          RTS

im3_pacman_task_c978:
C978: BD C3 0A    JSR    object_move_by_speed_c30a
C97B: BD F5 FA    JSR    pacman_anim_frame_f5fa
C97E: A6 4C       LDA    $C,U
C980: 81 F8       CMPA   #$F8
C982: 24 01       BCC    $C985
C984: 39          RTS
C985: CC 00 80    LDD    #$0080
C988: BD E2 BB    JSR    task_wait_init_e2bb
C98B: BD E2 C4    JSR    task_wait_e2c4
C98E: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C991: ED 44       STD    $4,U
C993: 10 8E C9 E2 LDY    #$C9E2
C997: 8E 01 00    LDX    #$0100
C99A: 86 01       LDA    #$01

im_spawn_4_actors_c99c:
C99C: 9F F8       STX    <$F8                   ; <$F8=temp / loop counter
C99E: 97 FA       STA    <$FA
C9A0: CE 08 10    LDU    #$0810
C9A3: C6 03       LDB    #$03
C9A5: E7 56       STB    -$A,U
C9A7: 86 03       LDA    #$03
C9A9: 3D          MUL
C9AA: 8E C9 D6    LDX    #$C9D6
C9AD: 3A          ABX
C9AE: A6 80       LDA    ,X+
C9B0: A7 4A       STA    $A,U
C9B2: EC 81       LDD    ,X++
C9B4: ED 4C       STD    $C,U
C9B6: CC 0E 30    LDD    #$0E30
C9B9: A7 49       STA    $9,U
C9BB: E7 4B       STB    $B,U
C9BD: 96 FA       LDA    <$FA
C9BF: A7 53       STA    -$D,U
C9C1: DC F8       LDD    <$F8                   ; <$F8=temp / loop counter
C9C3: ED 50       STD    -$10,U
C9C5: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
C9C8: ED 44       STD    $4,U
C9CA: 10 AF C4    STY    ,U
C9CD: E6 56       LDB    -$A,U
C9CF: 33 C8 20    LEAU   $20,U
C9D2: 5A          DECB
C9D3: 2A D0       BPL    $C9A5
C9D5: 39          RTS

C9E8: 4C          INCA
C9E9: 81 08       CMPA   #$08
C9EB: 25 01       BCS    $C9EE
C9ED: 39          RTS
C9EE: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
C9F1: ED 44       STD    $4,U
C9F3: 39          RTS

im_blink_colour_c9f4:
C9F4: D6 81       LDB    <$81                   ; <$81=frame counter
C9F6: 54          LSRB
C9F7: 54          LSRB
C9F8: C4 03       ANDB   #$03
C9FA: CB 30       ADDB   #$30
C9FC: E7 4B       STB    $B,U
C9FE: 39          RTS

im3_ghost_init_c9ff:
C9FF: CE 0E 90    LDU    #$0E90
CA02: CC 00 80    LDD    #$0080
CA05: ED 4C       STD    $C,U
CA07: CC 01 00    LDD    #$0100
CA0A: ED 50       STD    -$10,U
CA0C: 86 03       LDA    #$03
CA0E: A7 53       STA    -$D,U
CA10: CC 0C 04    LDD    #$0C04
CA13: A7 49       STA    $9,U
CA15: E7 4B       STB    $B,U
CA17: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
CA1A: ED 44       STD    $4,U
CA1C: CC CA 22    LDD    #$CA22                 ; [function_address] ; -> im3_ghost_task_ca22
CA1F: ED C4       STD    ,U
CA21: 39          RTS

im3_ghost_task_ca22:
CA22: CC 00 30    LDD    #$0030
CA25: BD E2 BB    JSR    task_wait_init_e2bb
CA28: BD E2 C4    JSR    task_wait_e2c4
CA2B: BD C3 0A    JSR    object_move_by_speed_c30a
CA2E: 96 81       LDA    <$81                   ; <$81=frame counter
CA30: 44          LSRA
CA31: 44          LSRA
CA32: 84 01       ANDA   #$01
CA34: 8B 6B       ADDA   #$6B
CA36: A7 4A       STA    $A,U
CA38: A6 4C       LDA    $C,U
CA3A: 81 F8       CMPA   #$F8
CA3C: 24 01       BCC    $CA3F
CA3E: 39          RTS
CA3F: 86 01       LDA    #$01
CA41: A7 53       STA    -$D,U
CA43: 86 08       LDA    #$08
CA45: A7 4B       STA    $B,U
CA47: BD E2 B4    JSR    task_yield_e2b4
CA4A: BD C3 0A    JSR    object_move_by_speed_c30a
CA4D: 96 81       LDA    <$81                   ; <$81=frame counter
CA4F: 44          LSRA
CA50: 44          LSRA
CA51: 84 01       ANDA   #$01
CA53: 8B 73       ADDA   #$73
CA55: A7 4A       STA    $A,U
CA57: A6 4C       LDA    $C,U
CA59: 81 08       CMPA   #$08
CA5B: 25 01       BCS    $CA5E
CA5D: 39          RTS
CA5E: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
CA61: ED 44       STD    $4,U
CA63: 39          RTS

im4_init_ca64:
CA64: 10 8E CA 70 LDY    #$CA70                 ; [function_address] ; -> im4_actor_task_ca70
CA68: 8E 01 80    LDX    #$0180
CA6B: 86 01       LDA    #$01
CA6D: 7E C9 9C    JMP    im_spawn_4_actors_c99c

im4_actor_task_ca70:
CA70: BD C3 0A    JSR    object_move_by_speed_c30a
CA73: BD C9 F4    JSR    im_blink_colour_c9f4
CA76: A6 4C       LDA    $C,U
CA78: 81 08       CMPA   #$08
CA7A: 25 01       BCS    $CA7D
CA7C: 39          RTS
CA7D: 6F 4C       CLR    $C,U
CA7F: CC 03 08    LDD    #$0308
CA82: A7 53       STA    -$D,U
CA84: E7 4B       STB    $B,U
CA86: CC 00 A0    LDD    #$00A0
CA89: BD E2 BB    JSR    task_wait_init_e2bb
CA8C: BD E2 C4    JSR    task_wait_e2c4
CA8F: BD C3 0A    JSR    object_move_by_speed_c30a
CA92: 96 81       LDA    <$81                   ; <$81=frame counter
CA94: 44          LSRA
CA95: 44          LSRA
CA96: 84 01       ANDA   #$01
CA98: 8B 73       ADDA   #$73
CA9A: A7 4A       STA    $A,U
CA9C: A6 4C       LDA    $C,U
CA9E: 81 F8       CMPA   #$F8
CAA0: 24 01       BCC    $CAA3
CAA2: 39          RTS
CAA3: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
CAA6: ED 44       STD    $4,U
CAA8: 39          RTS

im4_ghosts_init_caa9:
CAA9: CE 08 90    LDU    #$0890
CAAC: C6 1F       LDB    #$1F
CAAE: E7 56       STB    -$A,U
CAB0: C4 1C       ANDB   #$1C
CAB2: 54          LSRB
CAB3: 8E CA F4    LDX    #$CAF4
CAB6: EC 85       LDD    B,X
CAB8: ED 42       STD    $2,U
CABA: E6 56       LDB    -$A,U
CABC: C4 03       ANDB   #$03
CABE: 58          ASLB
CABF: 58          ASLB
CAC0: 58          ASLB
CAC1: 58          ASLB
CAC2: CB 68       ADDB   #$68
CAC4: 86 F8       LDA    #$F8
CAC6: ED 4C       STD    $C,U
CAC8: E6 56       LDB    -$A,U
CACA: 54          LSRB
CACB: 54          LSRB
CACC: EB 56       ADDB   -$A,U
CACE: C4 03       ANDB   #$03
CAD0: CB 04       ADDB   #$04
CAD2: E7 4B       STB    $B,U
CAD4: 86 02       LDA    #$02
CAD6: A7 49       STA    $9,U
CAD8: CC 01 80    LDD    #$0180
CADB: ED 50       STD    -$10,U
CADD: 86 01       LDA    #$01
CADF: A7 53       STA    -$D,U
CAE1: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
CAE4: ED 44       STD    $4,U
CAE6: CC CB 04    LDD    #$CB04                 ; [function_address] ; -> im4_ghost_task_cb04
CAE9: ED C4       STD    ,U
CAEB: E6 56       LDB    -$A,U
CAED: 33 C8 20    LEAU   $20,U
CAF0: 5A          DECB
CAF1: 2A BB       BPL    $CAAE
CAF3: 39          RTS

im4_ghost_task_cb04:
CB04: BD E2 C4    JSR    task_wait_e2c4
CB07: BD C3 0A    JSR    object_move_by_speed_c30a
CB0A: BD F8 4D    JSR    ghost_anim_frame_nocolour_f84d
CB0D: A6 4C       LDA    $C,U
CB0F: 81 08       CMPA   #$08
CB11: 25 01       BCS    $CB14
CB13: 39          RTS
CB14: CC 03 01    LDD    #$0301
CB17: A7 53       STA    -$D,U
CB19: E7 4B       STB    $B,U
CB1B: CC 00 A0    LDD    #$00A0
CB1E: BD E2 BB    JSR    task_wait_init_e2bb
CB21: BD E2 C4    JSR    task_wait_e2c4
CB24: 6F 56       CLR    -$A,U
CB26: BD C3 0A    JSR    object_move_by_speed_c30a
CB29: BD F5 FA    JSR    pacman_anim_frame_f5fa
CB2C: A6 4C       LDA    $C,U
CB2E: 81 F8       CMPA   #$F8
CB30: 24 01       BCC    $CB33
CB32: 39          RTS
CB33: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
CB36: ED 44       STD    $4,U
CB38: 39          RTS

im5_pacman_init_cb39:
CB39: 7F 16 26    CLR    $1626
CB3C: 8E F8 C0    LDX    #$F8C0                 ; NOT a function address: coordinates y=$F8 x=$C0
CB3F: CC 01 01    LDD    #$0101
CB42: BD F5 1E    JSR    pacman_object_setup_f51e
CB45: CC 00 C0    LDD    #$00C0
CB48: ED 50       STD    -$10,U
CB4A: 8E CB 50    LDX    #$CB50                 ; [function_address] ; -> im5_pacman_task_cb50
CB4D: AF C4       STX    ,U
CB4F: 39          RTS

im5_pacman_task_cb50:
CB50: BD C3 0A    JSR    object_move_by_speed_c30a
CB53: BD F5 FA    JSR    pacman_anim_frame_f5fa
CB56: A6 4C       LDA    $C,U
CB58: 81 80       CMPA   #$80
CB5A: 27 01       BEQ    $CB5D
CB5C: 39          RTS
CB5D: 86 0F       LDA    #$0F
CB5F: A7 4A       STA    $A,U
CB61: CC 00 0C    LDD    #$000C
CB64: BD E2 BB    JSR    task_wait_init_e2bb
CB67: BD E2 C4    JSR    task_wait_e2c4
CB6A: CC CB EB    LDD    #$CBEB                 ; [function_address] ; -> im5_pacman_anim_task_cbeb
CB6D: BD F7 7D    JSR    set_ghosts_state_f77d
CB70: CC F0 EF    LDD    #$F0EF                 ; [function_address] ; -> runner_hide_sprite_f0ef
CB73: ED 44       STD    $4,U
CB75: BD E2 B4    JSR    task_yield_e2b4
CB78: 39          RTS

im5_ghosts_init_cb79:
CB79: 10 8E 08 C0 LDY    #$08C0
CB7D: CE 0E 90    LDU    #$0E90
CB80: C6 03       LDB    #$03
CB82: E7 56       STB    -$A,U
CB84: 58          ASLB
CB85: 8E CB D9    LDX    #$CBD9
CB88: EC 85       LDD    B,X
CB8A: ED 42       STD    $2,U
CB8C: 10 AF 4C    STY    $C,U
CB8F: CC 00 E0    LDD    #$00E0
CB92: ED 50       STD    -$10,U
CB94: 86 03       LDA    #$03
CB96: A7 53       STA    -$D,U
CB98: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
CB9B: ED 44       STD    $4,U
CB9D: CC CB E1    LDD    #$CBE1                 ; [function_address] ; -> im5_ghost_task_cbe1
CBA0: ED C4       STD    ,U
CBA2: E6 56       LDB    -$A,U
CBA4: 33 C8 20    LEAU   $20,U
CBA7: 5A          DECB
CBA8: C1 01       CMPB   #$01
CBAA: 26 D6       BNE    $CB82
CBAC: 10 8E F8 C0 LDY    #$F8C0                 ; NOT a function address: coordinates y=$F8 x=$C0
CBB0: E7 56       STB    -$A,U
CBB2: 58          ASLB
CBB3: 8E CB D9    LDX    #$CBD9
CBB6: EC 85       LDD    B,X
CBB8: ED 42       STD    $2,U
CBBA: 10 AF 4C    STY    $C,U
CBBD: CC 00 E0    LDD    #$00E0
CBC0: ED 50       STD    -$10,U
CBC2: 86 01       LDA    #$01
CBC4: A7 53       STA    -$D,U
CBC6: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
CBC9: ED 44       STD    $4,U
CBCB: CC CB E1    LDD    #$CBE1                 ; [function_address] ; -> im5_ghost_task_cbe1
CBCE: ED C4       STD    ,U
CBD0: E6 56       LDB    -$A,U
CBD2: 33 C8 20    LEAU   $20,U
CBD5: 5A          DECB
CBD6: 2A D8       BPL    $CBB0
CBD8: 39          RTS

im5_ghost_task_cbe1:
CBE1: BD E2 C4    JSR    task_wait_e2c4
CBE4: BD C3 0A    JSR    object_move_by_speed_c30a
CBE7: BD F8 47    JSR    ghost_anim_frame_f847
CBEA: 39          RTS

im5_pacman_anim_task_cbeb:
CBEB: CC 00 24    LDD    #$0024
CBEE: 8E 02 24    LDX    #$0224
CBF1: BD CC 8C    JSR    im5_set_ghost_codes_cc8c
CBF4: CC 00 20    LDD    #$0020
CBF7: BD E2 BB    JSR    task_wait_init_e2bb
CBFA: BD E2 C4    JSR    task_wait_e2c4
CBFD: CC 02 24    LDD    #$0224
CC00: 8E 00 24    LDX    #$0024
CC03: BD CC 8C    JSR    im5_set_ghost_codes_cc8c
CC06: CC 00 20    LDD    #$0020
CC09: BD E2 BB    JSR    task_wait_init_e2bb
CC0C: BD E2 C4    JSR    task_wait_e2c4
CC0F: CC 00 24    LDD    #$0024
CC12: 8E 02 24    LDX    #$0224
CC15: 8D 75       BSR    im5_set_ghost_codes_cc8c
CC17: CC 00 20    LDD    #$0020
CC1A: BD E2 BB    JSR    task_wait_init_e2bb
CC1D: BD E2 C4    JSR    task_wait_e2c4
CC20: CC 02 24    LDD    #$0224
CC23: 8E 00 24    LDX    #$0024
CC26: 8D 64       BSR    im5_set_ghost_codes_cc8c
CC28: CC 00 20    LDD    #$0020
CC2B: BD E2 BB    JSR    task_wait_init_e2bb
CC2E: BD E2 C4    JSR    task_wait_e2c4
CC31: CC 00 28    LDD    #$0028
CC34: 8E 00 26    LDX    #$0026
CC37: 8D 53       BSR    im5_set_ghost_codes_cc8c
CC39: A6 56       LDA    -$A,U
CC3B: 81 03       CMPA   #$03
CC3D: 27 04       BEQ    $CC43
CC3F: BD E2 B4    JSR    task_yield_e2b4
CC42: 39          RTS
CC43: CC 5B 14    LDD    #$5B14
CC46: B7 01 76    STA    $0176
CC49: F7 05 76    STB    $0576
CC4C: CC 00 20    LDD    #$0020
CC4F: BD E2 BB    JSR    task_wait_init_e2bb
CC52: BD E2 C4    JSR    task_wait_e2c4
CC55: 8D 42       BSR    im5_spawn_actors_cc99
CC57: CC 00 20    LDD    #$0020
CC5A: BD E2 BB    JSR    task_wait_init_e2bb
CC5D: BD E2 C4    JSR    task_wait_e2c4
CC60: 86 20       LDA    #$20
CC62: B7 01 76    STA    $0176
CC65: 86 08       LDA    #$08
CC67: A7 4B       STA    $B,U
CC69: CC 00 26    LDD    #$0026
CC6C: 8E 00 30    LDX    #$0030
CC6F: 8D 1B       BSR    im5_set_ghost_codes_cc8c
CC71: CC 00 38    LDD    #$0038
CC74: BD E2 BB    JSR    task_wait_init_e2bb
CC77: BD E2 C4    JSR    task_wait_e2c4
CC7A: CC 55 08    LDD    #$5508
CC7D: ED 4A       STD    $A,U
CC7F: FD 0E FA    STD    $0EFA
CC82: FD 0E BA    STD    $0EBA
CC85: FD 0E DA    STD    $0EDA
CC88: BD E2 B4    JSR    task_yield_e2b4
CC8B: 39          RTS

im5_set_ghost_codes_cc8c:
CC8C: BF 0E 99    STX    $0E99
CC8F: FD 0E F9    STD    $0EF9
CC92: FD 0E B9    STD    $0EB9
CC95: FD 0E D9    STD    $0ED9
CC98: 39          RTS

im5_spawn_actors_cc99:
CC99: 10 8E CC E8 LDY    #$CCE8
CC9D: 8E 02 00    LDX    #$0200
CCA0: 86 02       LDA    #$02
CCA2: 9F F8       STX    <$F8                   ; <$F8=temp / loop counter
CCA4: 97 FA       STA    <$FA
CCA6: CE 08 10    LDU    #$0810
CCA9: C6 03       LDB    #$03
CCAB: E7 56       STB    -$A,U
CCAD: 86 03       LDA    #$03
CCAF: 3D          MUL
CCB0: 8E CC DC    LDX    #$CCDC
CCB3: 3A          ABX
CCB4: A6 80       LDA    ,X+
CCB6: A7 4A       STA    $A,U
CCB8: EC 81       LDD    ,X++
CCBA: ED 4C       STD    $C,U
CCBC: CC 0C 32    LDD    #$0C32
CCBF: A7 49       STA    $9,U
CCC1: E7 4B       STB    $B,U
CCC3: 96 FA       LDA    <$FA
CCC5: A7 53       STA    -$D,U
CCC7: DC F8       LDD    <$F8                   ; <$F8=temp / loop counter
CCC9: ED 50       STD    -$10,U
CCCB: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
CCCE: ED 44       STD    $4,U
CCD0: 10 AF C4    STY    ,U
CCD3: E6 56       LDB    -$A,U
CCD5: 33 C8 20    LEAU   $20,U
CCD8: 5A          DECB
CCD9: 2A D0       BPL    $CCAB
CCDB: 39          RTS

function_cceb:
CCEB: BD E2 BB    JSR    task_wait_init_e2bb
CCEE: BD C3 0A    JSR    object_move_by_speed_c30a
CCF1: BD E2 C4    JSR    task_wait_e2c4
CCF4: 86 00       LDA    #$00
CCF6: A7 53       STA    -$D,U
CCF8: CC 00 10    LDD    #$0010
CCFB: BD E2 BB    JSR    task_wait_init_e2bb
CCFE: BD C3 0A    JSR    object_move_by_speed_c30a
CD01: BD E2 C4    JSR    task_wait_e2c4
CD04: 86 02       LDA    #$02
CD06: A7 53       STA    -$D,U
CD08: CC 00 10    LDD    #$0010
CD0B: BD E2 BB    JSR    task_wait_init_e2bb
CD0E: BD C3 0A    JSR    object_move_by_speed_c30a
CD11: BD E2 C4    JSR    task_wait_e2c4
CD14: 86 00       LDA    #$00
CD16: A7 53       STA    -$D,U
CD18: CC 00 08    LDD    #$0008
CD1B: BD E2 BB    JSR    task_wait_init_e2bb
CD1E: BD C3 0A    JSR    object_move_by_speed_c30a
CD21: BD E2 C4    JSR    task_wait_e2c4
CD24: 86 02       LDA    #$02
CD26: A7 53       STA    -$D,U
CD28: CC 00 08    LDD    #$0008
CD2B: BD E2 BB    JSR    task_wait_init_e2bb
CD2E: BD C3 0A    JSR    object_move_by_speed_c30a
CD31: BD E2 C4    JSR    task_wait_e2c4
CD34: CC 00 20    LDD    #$0020
CD37: BD E2 BB    JSR    task_wait_init_e2bb
CD3A: BD E2 C4    JSR    task_wait_e2c4
CD3D: 86 31       LDA    #$31
CD3F: A7 4B       STA    $B,U
CD41: BD E2 B4    JSR    task_yield_e2b4
CD44: 39          RTS

;----------------------------------------------------------------------------
; New game: level/round counters, rank from the dip switches (table $CD7B -> $10B0).
;----------------------------------------------------------------------------
new_game_level_init_cd45:
CD45: CC 00 00    LDD    #$0000
CD48: 97 12       STA    <$12                   ; <$12=rank table index
CD4A: 97 1A       STA    <$1A                   ; <$1A=levels played (max 12)
CD4C: DD 1C       STD    <$1C                   ; <$1C=rank frozen after death
CD4E: DD 18       STD    <$18                   ; <$18=intermission schedule index
CD50: 4C          INCA
CD51: 97 03       STA    <$03                   ; <$03=level (BCD)
CD53: 97 13       STA    <$13                   ; <$13=round number (BCD)
CD55: CC 04 02    LDD    #$0402
CD58: DD 14       STD    <$14                   ; <$14=maze colour
CD5A: 86 03       LDA    #$03
CD5C: 97 17       STA    <$17
CD5E: D6 D1       LDB    <$D1                   ; <$D1=difficulty rank setting
CD60: C0 0C       SUBB   #$0C
CD62: 24 01       BCC    $CD65
CD64: 39          RTS
CD65: 86 06       LDA    #$06
CD67: 3D          MUL
CD68: 8E CD 7B    LDX    #$CD7B
CD6B: 3A          ABX
CD6C: CE 10 B0    LDU    #$10B0
CD6F: 10 8E 00 03 LDY    #$0003
CD73: BD CE 6A    JSR    copy_words_ce6a
CD76: 96 B0       LDA    <$B0
CD78: 97 1B       STA    <$1B                   ; <$1B=current rank
CD7A: 39          RTS

;----------------------------------------------------------------------------
; Automatic difficulty (rank C-F dips): raise the rank at each level (not after a death).
;----------------------------------------------------------------------------
auto_rank_update_cd93:
CD93: 96 D1       LDA    <$D1                   ; <$D1=difficulty rank setting
CD95: 81 0C       CMPA   #$0C
CD97: 24 01       BCC    $CD9A
CD99: 39          RTS
CD9A: 96 1C       LDA    <$1C                   ; <$1C=rank frozen after death
CD9C: 27 03       BEQ    $CDA1
CD9E: 0F 1C       CLR    <$1C                   ; <$1C=rank frozen after death
CDA0: 39          RTS
CDA1: 96 1B       LDA    <$1B                   ; <$1B=current rank
CDA3: 8E 10 B1    LDX    #$10B1
CDA6: D6 1D       LDB    <$1D                   ; <$1D=rank step
CDA8: AB 85       ADDA   B,X
CDAA: 91 B5       CMPA   <$B5
CDAC: 25 02       BCS    $CDB0
CDAE: 96 B5       LDA    <$B5
CDB0: 97 1B       STA    <$1B                   ; <$1B=current rank
CDB2: 39          RTS

auto_rank_on_death_cdb3:
CDB3: 86 01       LDA    #$01
CDB5: 97 1C       STA    <$1C                   ; <$1C=rank frozen after death
CDB7: 96 1D       LDA    <$1D                   ; <$1D=rank step
CDB9: 81 03       CMPA   #$03
CDBB: 26 01       BNE    $CDBE
CDBD: 39          RTS
CDBE: 0C 1D       INC    <$1D                   ; <$1D=rank step
CDC0: 39          RTS

;----------------------------------------------------------------------------
; Next level: advance counters, rank, and copy the level parameters (speeds, timers) from $D272 / $CFF2 into $1094-$10A9.
;----------------------------------------------------------------------------
next_level_cdc1:
CDC1: 8D 4D       BSR    advance_level_counters_ce10
CDC3: 8D CE       BSR    auto_rank_update_cd93

load_level_params_cdc5:
CDC5: 8D 13       BSR    load_rank_params_cdda
CDC7: 96 94       LDA    <$94                   ; <$94=level parameter index
CDC9: C6 0C       LDB    #$0C
CDCB: 3D          MUL
CDCC: 8E D2 72    LDX    #$D272
CDCF: 3A          ABX
CDD0: CE 10 9E    LDU    #$109E
CDD3: 10 8E 00 06 LDY    #$0006
CDD7: 7E CE 6A    JMP    copy_words_ce6a

load_rank_params_cdda:
CDDA: D6 D1       LDB    <$D1                   ; <$D1=difficulty rank setting
CDDC: 58          ASLB
CDDD: 8E CE 7D    LDX    #$CE7D
CDE0: AE 85       LDX    B,X
CDE2: 96 12       LDA    <$12                   ; <$12=rank table index
CDE4: A6 86       LDA    A,X
CDE6: 2A 06       BPL    $CDEE
CDE8: 84 7F       ANDA   #$7F
CDEA: 97 12       STA    <$12                   ; <$12=rank table index
CDEC: 20 F6       BRA    $CDE4
CDEE: 8D 0E       BSR    load_speed_params_cdfe
CDF0: 96 D1       LDA    <$D1                   ; <$D1=difficulty rank setting
CDF2: 81 0C       CMPA   #$0C
CDF4: 24 01       BCC    $CDF7
CDF6: 39          RTS
CDF7: 96 96       LDA    <$96                   ; <$96=bonus stage flag
CDF9: 27 01       BEQ    $CDFC
CDFB: 39          RTS
CDFC: 96 1B       LDA    <$1B                   ; <$1B=current rank

load_speed_params_cdfe:
CDFE: C6 0A       LDB    #$0A
CE00: 3D          MUL
CE01: 8E CF F2    LDX    #$CFF2
CE04: 30 8B       LEAX   D,X
CE06: CE 10 94    LDU    #$1094
CE09: 10 8E 00 05 LDY    #$0005
CE0D: 7E CE 6A    JMP    copy_words_ce6a

;----------------------------------------------------------------------------
; Advance level counters: level BCD, rank index, round (max 16), maze colour, bonus item type, item history ($1008, 7 icons).
;----------------------------------------------------------------------------
advance_level_counters_ce10:
CE10: 96 03       LDA    <$03                   ; <$03=level (BCD)
CE12: 8B 01       ADDA   #$01
CE14: 19          DAA
CE15: 97 03       STA    <$03                   ; <$03=level (BCD)
CE17: 0C 12       INC    <$12                   ; <$12=rank table index
CE19: 96 1A       LDA    <$1A                   ; <$1A=levels played (max 12)
CE1B: 81 0C       CMPA   #$0C
CE1D: 27 02       BEQ    $CE21
CE1F: 0C 1A       INC    <$1A                   ; <$1A=levels played (max 12)
CE21: 96 13       LDA    <$13                   ; <$13=round number (BCD)
CE23: 81 16       CMPA   #$16
CE25: 27 05       BEQ    $CE2C
CE27: 8B 01       ADDA   #$01
CE29: 19          DAA
CE2A: 97 13       STA    <$13                   ; <$13=round number (BCD)
CE2C: 0A 17       DEC    <$17
CE2E: 26 0E       BNE    $CE3E
CE30: 86 04       LDA    #$04
CE32: 97 17       STA    <$17
CE34: 0C 16       INC    <$16
CE36: 96 16       LDA    <$16
CE38: 80 04       SUBA   #$04
CE3A: 26 02       BNE    $CE3E
CE3C: 97 16       STA    <$16
CE3E: 0A 15       DEC    <$15
CE40: 26 0F       BNE    $CE51
CE42: 86 04       LDA    #$04
CE44: 97 15       STA    <$15
CE46: 96 14       LDA    <$14                   ; <$14=maze colour
CE48: 4C          INCA
CE49: 81 09       CMPA   #$09
CE4B: 26 02       BNE    $CE4F
CE4D: 86 04       LDA    #$04
CE4F: 97 14       STA    <$14                   ; <$14=maze colour
CE51: 0C 10       INC    <$10                   ; <$10=bonus item type of the level
CE53: 96 10       LDA    <$10                   ; <$10=bonus item type of the level
CE55: 80 10       SUBA   #$10
CE57: 26 02       BNE    $CE5B
CE59: 97 10       STA    <$10                   ; <$10=bonus item type of the level
CE5B: 96 11       LDA    <$11                   ; <$11=item history count
CE5D: 81 07       CMPA   #$07
CE5F: 26 12       BNE    $CE73
CE61: CE 10 08    LDU    #$1008
CE64: 30 41       LEAX   $1,U
CE66: 10 8E 00 04 LDY    #$0004

;----------------------------------------------------------------------------
; Copy Y words from (X) to (U).
;----------------------------------------------------------------------------
copy_words_ce6a:
CE6A: EC 81       LDD    ,X++
CE6C: ED C1       STD    ,U++
CE6E: 31 3F       LEAY   -$1,Y
CE70: 26 F8       BNE    copy_words_ce6a
CE72: 39          RTS
CE73: 0C 11       INC    <$11                   ; <$11=item history count
CE75: DC 10       LDD    <$10                   ; <$10=bonus item type of the level
CE77: 8E 10 08    LDX    #$1008
CE7A: A7 85       STA    B,X
CE7C: 39          RTS

;----------------------------------------------------------------------------
; RESET. Hardware init (IRQs off, sound CPU and I/O chips in reset),
; DP = $10, SP = $1200, then the power-up tests: RAM ($0000-$1FFF),
; sound RAM ($4040-$43FF), I/O chips, ROM checksums (table $E1DA), sound CPU
; handshake ('OO' in $4040/$4041). Errors print a code and hang.
;----------------------------------------------------------------------------
init_e000:		; [global]
E000: 1A 10       ORCC   #$10                   ; IRQ off
E001: 10 B7 50 00 STA    latch_sub_irq_off_5000 ; sound CPU IRQ off
E005: B7 50 02    STA    latch_main_irq_off_5002 ; main IRQ off
E008: B7 50 08    STA    latch_io_reset_5008    ; I/O chips in reset
E00B: B7 50 0A    STA    latch_sub_reset_500a   ; sound CPU in reset
E00E: B7 50 06    STA    latch_sound_off_5006   ; sound off
E011: 86 10       LDA    #$10                   ; DP = $10 : "<$xx" = $10xx
E013: 1F 8B       TFR    A,DP
E015: 10 CE 12 00 LDS    #$1200                 ; stack
E019: CC 00 00    LDD    #$0000
E01C: B7 20 00    STA    flip_screen_2000
E01F: CE 00 00    LDU    #$0000
E022: B7 80 00    STA    watchdog_8000
E025: AE C9 E0 00 LDX    -$2000,U               ; read in E000
E029: 30 8B       LEAX   D,X
E02B: AF C1       STX    ,U++
E02D: 11 83 20 00 CMPU   #$2000
E031: 26 EF       BNE    $E022
E033: CE 00 00    LDU    #$0000
E036: B7 80 00    STA    watchdog_8000
E039: AE C9 E0 00 LDX    -$2000,U
E03D: 30 8B       LEAX   D,X
E03F: AC C1       CMPX   ,U++
E041: 26 0D       BNE    $E050
E043: 11 83 20 00 CMPU   #$2000
E047: 26 ED       BNE    $E036
E049: C3 11 11    ADDD   #$1111
E04C: 24 D1       BCC    $E01F
E04E: 20 02       BRA    $E052
E050: 33 5E       LEAU   -$2,U
E052: 1F 30       TFR    U,D
E054: 44          LSRA
E055: 44          LSRA
E056: 44          LSRA
E057: 8B 31       ADDA   #$31
E059: 8E 00 00    LDX    #$0000
E05C: CE 20 20    LDU    #$2020
E05F: B7 80 00    STA    watchdog_8000
E062: EF 81       STU    ,X++
E064: 8C 04 00    CMPX   #$0400
E067: 26 F6       BNE    $E05F
E069: CE 02 02    LDU    #$0202
E06C: B7 80 00    STA    watchdog_8000
E06F: EF 81       STU    ,X++
E071: 8C 08 00    CMPX   #$0800
E074: 26 F6       BNE    $E06C
E076: CE 00 00    LDU    #$0000
E079: B7 80 00    STA    watchdog_8000
E07C: EF 81       STU    ,X++
E07E: 8C 20 00    CMPX   #$2000
E081: 26 F6       BNE    $E079
E083: 8E E1 7D    LDX    #$E17D
E086: EE 81       LDU    ,X++
E088: 27 0E       BEQ    $E098
E08A: B7 80 00    STA    watchdog_8000
E08D: E6 80       LDB    ,X+
E08F: 27 F5       BEQ    $E086
E091: E7 C4       STB    ,U
E093: 33 C8 E0    LEAU   -$20,U
E096: 20 F2       BRA    $E08A
E098: 81 35       CMPA   #$35
E09A: 10 26 00 D2 LBNE   boot_error_e170
E09E: CC 00 00    LDD    #$0000
E0A1: CE 40 40    LDU    #$4040
E0A4: B7 80 00    STA    watchdog_8000
E0A7: AE C9 A0 00 LDX    -$6000,U
E0AB: 30 8B       LEAX   D,X
E0AD: AF C1       STX    ,U++
E0AF: 11 83 44 00 CMPU   #$4400
E0B3: 26 EF       BNE    $E0A4
E0B5: CE 40 40    LDU    #$4040
E0B8: B7 80 00    STA    watchdog_8000
E0BB: AE C9 A0 00 LDX    -$6000,U
E0BF: 30 8B       LEAX   D,X
E0C1: AC C1       CMPX   ,U++
E0C3: 26 0D       BNE    $E0D2
E0C5: 11 83 44 00 CMPU   #$4400
E0C9: 26 ED       BNE    $E0B8
E0CB: C3 11 11    ADDD   #$1111
E0CE: 24 D1       BCC    $E0A1
E0D0: 20 1A       BRA    $E0EC
E0D2: 1F 10       TFR    X,D
E0D4: A8 5E       EORA   -$2,U
E0D6: 27 09       BEQ    $E0E1
E0D8: 81 10       CMPA   #$10
E0DA: 24 0B       BCC    $E0E7
E0DC: 86 36       LDA    #$36
E0DE: 7E E1 70    JMP    boot_error_e170
E0E1: E8 5F       EORB   -$1,U
E0E3: C1 10       CMPB   #$10
E0E5: 25 F5       BCS    $E0DC
E0E7: 86 35       LDA    #$35
E0E9: 7E E1 70    JMP    boot_error_e170
E0EC: 4F          CLRA
E0ED: 8E 48 00    LDX    #$4800
E0F0: B7 80 00    STA    watchdog_8000
E0F3: 1F 89       TFR    A,B
E0F5: EB 89 98 00 ADDB   -$6800,X
E0F9: E7 80       STB    ,X+
E0FB: 8C 48 20    CMPX   #$4820
E0FE: 26 F0       BNE    $E0F0
E100: 8E 48 00    LDX    #$4800
E103: B7 80 00    STA    watchdog_8000
E106: 1F 89       TFR    A,B
E108: EB 89 98 00 ADDB   -$6800,X
E10C: E8 80       EORB   ,X+
E10E: C4 0F       ANDB   #$0F
E110: 26 5C       BNE    $E16E
E112: 8C 48 20    CMPX   #$4820
E115: 26 EC       BNE    $E103
E117: 8B 11       ADDA   #$11
E119: 24 D2       BCC    $E0ED
E11B: 86 31       LDA    #$31
E11D: CE E1 DA    LDU    #$E1DA
E120: 8E C0 00    LDX    #$C000
E123: 5F          CLRB
E124: 10 8E 20 00 LDY    #$2000
E128: B7 80 00    STA    watchdog_8000
E12B: EB 80       ADDB   ,X+
E12D: 31 3F       LEAY   -$1,Y
E12F: 26 F7       BNE    $E128
E131: E1 C0       CMPB   ,U+
E133: 26 40       BNE    $E175
E135: 4C          INCA
E136: 81 33       CMPA   #$33
E138: 26 E9       BNE    $E123
E13A: 8E 00 00    LDX    #$0000
E13D: BF 40 40    STX    $4040                  ; sound CPU handshake
E140: B7 50 0B    STA    latch_sub_run_500b     ; start the sound CPU
E143: B7 80 00    STA    watchdog_8000
E146: 86 33       LDA    #$33
E148: 30 1F       LEAX   -$1,X
E14A: 27 29       BEQ    $E175
E14C: B6 40 41    LDA    $4041
E14F: 27 F2       BEQ    $E143
E151: 81 4F       CMPA   #$4F
E153: 26 20       BNE    $E175
E155: B6 40 40    LDA    $4040
E158: 81 4F       CMPA   #$4F
E15A: 26 14       BNE    boot_error_e170
E15C: CC 4F 4B    LDD    #$4F4B
E15F: B7 01 62    STA    $0162
E162: F7 01 42    STB    $0142
E165: B7 02 62    STA    $0262
E168: F7 02 42    STB    $0242
E16B: 7E E1 DD    JMP    boot_start_tasks_e1dd
E16E: 86 37       LDA    #$37

boot_error_e170:
E170: B7 02 62    STA    $0262
E173: 20 03       BRA    $E178
E175: B7 01 62    STA    $0162
E178: B7 80 00    STA    watchdog_8000
E17B: 20 FB       BRA    $E178

;----------------------------------------------------------------------------
; Start of the multitasking: 6 task slots of 8 bytes at $1100 are filled
; from the table $E288 (resume PC) with runner runner_resume_f0de, the
; I/O chips, sound and IRQ are enabled, then the MAIN LOOP (not in the IRQ):
;   wait vblank flag <$80 (set by the IRQ), frame counter <$81++,
;   run_tasks_e224, blink 1UP/2UP, credits display, coin->start check.
;----------------------------------------------------------------------------
boot_start_tasks_e1dd:
E1DD: CC 00 00    LDD    #$0000
E1E0: FD 40 40    STD    $4040
E1E3: CE 48 00    LDU    #$4800
E1E6: 8E 00 10    LDX    #$0010
E1E9: BD EE B1    JSR    fill_words_eeb1
E1EC: 4A          DECA
E1ED: 97 86       STA    <$86                   ; <$86=player-up blink control
E1EF: B7 50 09    STA    latch_io_run_5009      ; I/O chips run
E1F2: B7 50 03    STA    latch_main_irq_on_5003 ; main IRQ on
E1F5: B7 50 07    STA    latch_sound_on_5007    ; sound on
E1F8: CE 11 00    LDU    #$1100
E1FB: 10 8E E2 88 LDY    #$E288                 ; initial task PCs (table in the listing gap)
E1FF: C6 06       LDB    #$06
E201: AE A1       LDX    ,Y++
E203: AF C4       STX    ,U
E205: 8E F0 DE    LDX    #$f0de                 ; [function_address] ; runner = resume coroutine ; -> runner_resume_f0de
E208: AF 44       STX    $4,U
E20A: 33 48       LEAU   $8,U
E20C: 5A          DECB
E20D: 26 F2       BNE    $E201
E20F: 1C EF       ANDCC  #$EF                   ; interrupts on

main_loop_e211:
E211: 96 80       LDA    <$80                   ; wait for vblank ; <$80=vblank flag (set by IRQ)
E213: 27 FC       BEQ    main_loop_e211
E215: 0A 80       DEC    <$80                   ; <$80=vblank flag (set by IRQ)
E217: 0C 81       INC    <$81                   ; <$81=frame counter
E219: 8D 09       BSR    run_tasks_e224
E21B: BD FE 76    JSR    blink_player_up_fe76
E21E: 8D 3D       BSR    draw_credits_e25d
E220: 8D 53       BSR    check_coin_start_e275
E222: 20 ED       BRA    main_loop_e211

;----------------------------------------------------------------------------
; Run the tasks of slots 1..5 ($1108-$1128): JSR [4,U] = the slot RUNNER
; (runner_resume_f0de, or task_nop_rts_e2ba when paused), which itself
; resumes the task coroutine with JSR [,U].
; DSW 'freeze' on (<$C6 bit 7): freeze_rack_test_e237 instead.
;----------------------------------------------------------------------------
run_tasks_e224:
E224: CE 11 08    LDU    #$1108
E227: 96 C6       LDA    <$C6                   ; <$C6=DSW1 (rank, coin B, demo sound, freeze)
E229: 2B 0C       BMI    freeze_rack_test_e237
E22B: AD D8 04    JSR    [$04,U]                ; [indirect_jump] ; call the slot runner
E22E: 33 48       LEAU   $8,U
E230: 11 83 11 30 CMPU   #$1130
E234: 26 F5       BNE    $E22B
E236: 39          RTS

; doesn't seem reached at least right away

;----------------------------------------------------------------------------
; Freeze / rack test dip ON: no task runs (everything frozen) except while
; the game is in its play loop (slot 1 = game_play_loop_e844): then the
; button makes slot 0 run level_cleared_e858 (skip the level) and the
; other slots 2-5 keep running.
;----------------------------------------------------------------------------
freeze_rack_test_e237:
E237: AE C4       LDX    ,U
E239: 8C E8 44    CMPX   #$E844                 ; [function_address] ; -> game_play_loop_e844
E23C: 27 01       BEQ    $E23F
E23E: 39          RTS
E23F: CE 11 00    LDU    #$1100
E242: 96 AC       LDA    <$AC                   ; <$AC=current controls (active high)
E244: 85 10       BITA   #$10
E246: 27 05       BEQ    $E24D
E248: 8E E8 58    LDX    #$E858                 ; [function_address] ; -> level_cleared_e858
E24B: AF C4       STX    ,U
E24D: AE C4       LDX    ,U
E24F: 8C E8 44    CMPX   #$E844                 ; [function_address] ; -> game_play_loop_e844
E252: 26 01       BNE    $E255
E254: 39          RTS
E255: AD D8 04    JSR    [$04,U]                ; [indirect_jump]
E258: CE 11 10    LDU    #$1110
E25B: 20 CE       BRA    $E22B

draw_credits_e25d:
E25D: 96 C0       LDA    <$C0                   ; <$C0=credits
E25F: 4C          INCA
E260: 26 01       BNE    $E263
E262: 39          RTS
E263: 96 C7       LDA    <$C7                   ; <$C7=attract flag
E265: 26 01       BNE    $E268
E267: 39          RTS
E268: 8E 10 C0    LDX    #$10C0
E26B: CE 00 35    LDU    #$0035
E26E: 10 8E 01 01 LDY    #$0101
E272: 7E FE 18    JMP    print_bcd_vert_fe18

check_coin_start_e275:
E275: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
E277: 27 01       BEQ    $E27A
E279: 39          RTS
E27A: 96 C0       LDA    <$C0                   ; <$C0=credits
E27C: 26 01       BNE    $E27F
E27E: 39          RTS
E27F: 0C 8B       INC    <$8B                   ; <$8B=game sounds enabled (0 in attract)
E281: CC E7 16    LDD    #$e716                 ; [function_address] ; coin -> slot 1 task = task_credit_inserted_e716 ; -> task_credit_inserted_e716
E284: FD 11 08    STD    task_slot1_1108
E287: 39          RTS

;----------------------------------------------------------------------------
; Object manager off: slot 2 and slot 5 tasks := task_nop_rts_e2ba.
;----------------------------------------------------------------------------
disable_object_tasks_e294:
E294: CC E2 BA    LDD    #$e2ba                 ; [function_address] ; -> task_nop_rts_e2ba
E297: FD 11 10    STD    task_slot2_1110
E29A: FD 11 28    STD    task_slot5_1128
E29D: 39          RTS

;----------------------------------------------------------------------------
; Object manager on: slot 2 task = object_manager_task_f085, slot 5 task = task_idle_fd3a (runner $112C = resume).
;----------------------------------------------------------------------------
enable_object_tasks_e29e:
E29E: CC F0 85    LDD    #$f085                 ; [function_address] ; -> object_manager_task_f085
E2A1: FD 11 10    STD    task_slot2_1110
E2A4: CC FD 3A    LDD    #$fd3a                 ; [function_address] ; -> task_idle_fd3a
E2A7: FD 11 28    STD    task_slot5_1128
E2AA: CC F0 DE    LDD    #$f0de                 ; [function_address] ; -> runner_resume_f0de
E2AD: FD 11 2C    STD    $112C
E2B0: 7F 40 4E    CLR    $404E
E2B3: 39          RTS

; when called, store return address somewhere and returns to caller of caller

;----------------------------------------------------------------------------
; TASK YIELD (was 'stack_set_e2b4'). JSR here from the task coroutine: the
; return address is stored in the task record (,U) and the RTS goes back to
; the runner (runner_resume_f0de: PSHS U / JSR [,U]). Next frame the task
; continues after the JSR. ONLY THE PC IS SAVED: registers are lost, all
; state must be kept in the record (U is restored by the runner), and the
; yield must be done at the top level of the task (nothing else pushed).
;----------------------------------------------------------------------------
task_yield_e2b4:
E2B4: 35 10       PULS   X                      ; put return address in X / pops the stack
E2B6: EE 62       LDU    $2,S                   ; load U as contents of S+2 (ex: $1108)
E2B8: AF C4       STX    ,U                     ; store return address in (U)

;----------------------------------------------------------------------------
; RTS: used as a 'do nothing' state / runner (was func_e2ba / l_e2ba).
;----------------------------------------------------------------------------
task_nop_rts_e2ba:
E2BA: 39          RTS                           ; and returns to caller of caller (F0E2, after JSR [,U])

; same as above but with added a parameter (D) which seems to be a counter

;----------------------------------------------------------------------------
; WAIT D FRAMES, part 1 (was 'stack_set_with_param_e2bb'): counter 2,U = D
; and resume PC = next instruction, then returns to the caller normally.
; Always followed (possibly after other calls executed every frame) by:
;----------------------------------------------------------------------------
task_wait_init_e2bb:
E2BB: 35 10       PULS   X                      ; put return address in X
E2BD: EE 62       LDU    $2,S                   ; put stack value from U+2
E2BF: ED 42       STD    $2,U                   ; store D in U+2
E2C1: AF C4       STX    ,U                     ; store return address in U
E2C3: 39          RTS                           ; and returns to caller

;----------------------------------------------------------------------------
; WAIT D FRAMES, part 2 (was 'stack_set_with_param_decrease_e2c4'):
; counter 2,U -1; not zero -> yield (RTS to the runner, the task resumes
; at the instruction after JSR task_wait_init_e2bb, so the code between
; the two calls runs every frame). Zero -> continue after this JSR.
;----------------------------------------------------------------------------
task_wait_e2c4:
E2C4: 35 10       PULS   X                      ; put return address in X
E2C6: EE 62       LDU    $2,S                   ; put stack value from U+2
E2C8: EC 42       LDD    $2,U                   ; get D from U+2
E2CA: 83 00 01    SUBD   #$0001                 ; D-- (decrease our counter parameter)
E2CD: ED 42       STD    $2,U                   ; store new value of D
E2CF: 27 01       BEQ    $E2D2                  ; if 0, countdown done, branch
E2D1: 39          RTS
E2D2: AF C4       STX    ,U                     ; store return address in U
E2D4: 6E 84       JMP    ,X                     ; and returns to caller without popping the stack

;----------------------------------------------------------------------------
; IRQ (vblank). Watchdog, IRQ acknowledge (latch bit 1 off/on), vblank flag
; <$80 = 1 for the main loop, flip screen, SPRITE DOUBLE BUFFER: copies
; the sprite lists $0F00-$0F7F, $1700-$177F, $1F00-$1F7F to $0F80/$1780/$1F80
; (the ones the video hardware reads), handles the two Namco I/O chips,
; controls / demo (irq_input_handler_c537), service switch -> reset.
;----------------------------------------------------------------------------
irq_vblank_e2d6:
E2D6: B7 80 00    STA    watchdog_8000
E2D9: B7 50 02    STA    latch_main_irq_off_5002 ; IRQ acknowledge
E2DC: B7 50 03    STA    latch_main_irq_on_5003
E2DF: 86 01       LDA    #$01                   ; vblank flag for the main loop
E2E1: 97 80       STA    <$80                   ; <$80=vblank flag (set by IRQ)
E2E3: B7 40 FB    STA    $40FB
E2E6: 96 83       LDA    <$83                   ; <$83=cocktail cabinet
E2E8: 94 84       ANDA   <$84                   ; <$84=current player (0/1)
E2EA: 97 85       STA    <$85                   ; <$85=screen flipped (cocktail P2)
E2EC: B7 20 00    STA    flip_screen_2000
E2EF: 8E 0F 80    LDX    #$0F80                 ; sprite double buffer copy
E2F2: CE 17 80    LDU    #$1780
E2F5: 10 8E 1F 80 LDY    #$1F80
E2F9: EC 88 80    LDD    -$80,X
E2FC: ED 81       STD    ,X++
E2FE: EC C8 80    LDD    -$80,U
E301: ED C1       STD    ,U++
E303: EC A8 80    LDD    -$80,Y
E306: ED A1       STD    ,Y++
E308: 8C 10 00    CMPX   #$1000
E30B: 26 EC       BNE    $E2F9
E30D: CE 48 00    LDU    #$4800
E310: 8D 15       BSR    namco_io_dispatch_e327
E312: CE 48 10    LDU    #$4810
E315: 8D 10       BSR    namco_io_dispatch_e327
E317: BD C5 37    JSR    irq_input_handler_c537
E31A: 96 E8       LDA    <$E8                   ; <$E8=service mode flag
E31C: 27 08       BEQ    $E326
E31E: 96 C4       LDA    <$C4                   ; <$C4=DSW0 / service bits
E320: 85 08       BITA   #$08
E322: 10 26 FC DA LBNE   init_e000              ; service switch -> reset
E326: 3B          RTI

;----------------------------------------------------------------------------
; Namco 56XX I/O chip handler: dispatch on the chip mode register (+8): 1 controls, 4 coins, 8 self test, 9 dips.
;----------------------------------------------------------------------------
namco_io_dispatch_e327:
E327: A6 48       LDA    $8,U
E329: 84 0F       ANDA   #$0F
E32B: 48          ASLA
E32C: 8E E3 31    LDX    #jump_table_e331
E32F: 6E 96       JMP    [A,X]                  ; [indirect_jump] [nb_entries=16]

;----------------------------------------------------------------------------
; Jump table indexed by the I/O chip mode (16 entries).
;----------------------------------------------------------------------------
jump_table_e331:
	dc.w	task_nop_rts_e2ba
	dc.w	io_read_controls_e351
	dc.w	task_nop_rts_e2ba
	dc.w	task_nop_rts_e2ba
	dc.w	io_read_coins_e369
	dc.w	task_nop_rts_e2ba
	dc.w	task_nop_rts_e2ba
	dc.w	task_nop_rts_e2ba
	dc.w	io_self_test_e3a4
	dc.w	io_read_dips_e3d8
	dc.w	task_nop_rts_e2ba
	dc.w	task_nop_rts_e2ba
	dc.w	task_nop_rts_e2ba
	dc.w	task_nop_rts_e2ba
	dc.w	task_nop_rts_e2ba
	dc.w	task_nop_rts_e2ba

io_read_controls_e351:
E351: 8E 10 DE    LDX    #$10DE
E354: A6 80       LDA    ,X+
E356: A7 84       STA    ,X
E358: 30 1E       LEAX   -$2,X
E35A: 8C 10 D7    CMPX   #$10D7
E35D: 26 F5       BNE    $E354
E35F: 8E 10 D8    LDX    #$10D8
E362: 8D 31       BSR    io_merge_nibbles_e395
E364: 8E 10 DC    LDX    #$10DC
E367: 20 2C       BRA    io_merge_nibbles_e395

io_read_coins_e369:
E369: 8E 10 C0    LDX    #$10C0
E36C: A6 84       LDA    ,X
E36E: A7 01       STA    $1,X
E370: EC C4       LDD    ,U
E372: 1E 89       EXG    A,B
E374: 8D 21       BSR    io_merge_nibbles2_e397
E376: A1 80       CMPA   ,X+
E378: 25 0F       BCS    $E389
E37A: 86 99       LDA    #$99
E37C: A0 1F       SUBA   -$1,X
E37E: 8B 01       ADDA   #$01
E380: 19          DAA
E381: AB 1E       ADDA   -$2,X
E383: 19          DAA
E384: 84 0F       ANDA   #$0F
E386: B7 40 82    STA    $4082
E389: 33 44       LEAU   $4,U
E38B: A6 84       LDA    ,X
E38D: A7 01       STA    $1,X
E38F: 96 85       LDA    <$85                   ; <$85=screen flipped (cocktail P2)
E391: 27 02       BEQ    io_merge_nibbles_e395
E393: 33 42       LEAU   $2,U

io_merge_nibbles_e395:
E395: EC C1       LDD    ,U++

io_merge_nibbles2_e397:
E397: 58          ASLB
E398: 58          ASLB
E399: 58          ASLB
E39A: 58          ASLB
E39B: E7 84       STB    ,X
E39D: 84 0F       ANDA   #$0F
E39F: AB 84       ADDA   ,X
E3A1: A7 80       STA    ,X+
E3A3: 39          RTS

io_self_test_e3a4:
E3A4: EC C4       LDD    ,U
E3A6: 43          COMA
E3A7: 48          ASLA
E3A8: 48          ASLA
E3A9: 48          ASLA
E3AA: 48          ASLA
E3AB: 97 EB       STA    <$EB
E3AD: 53          COMB
E3AE: C4 0F       ANDB   #$0F
E3B0: DB EB       ADDB   <$EB
E3B2: D7 EB       STB    <$EB
E3B4: 33 49       LEAU   $9,U
E3B6: C6 07       LDB    #$07
E3B8: A6 C0       LDA    ,U+
E3BA: 84 0F       ANDA   #$0F
E3BC: 9B EB       ADDA   <$EB
E3BE: 97 EB       STA    <$EB
E3C0: 5A          DECB
E3C1: 26 F5       BNE    $E3B8
E3C3: 0C EB       INC    <$EB
E3C5: 26 01       BNE    $E3C8
E3C7: 39          RTS
E3C8: 1F 30       TFR    U,D
E3CA: 54          LSRB
E3CB: 54          LSRB
E3CC: 54          LSRB
E3CD: 54          LSRB
E3CE: CB 30       ADDB   #$30
E3D0: F7 02 64    STB    $0264
E3D3: B7 80 00    STA    watchdog_8000
E3D6: 20 FB       BRA    $E3D3

io_read_dips_e3d8:
E3D8: 8E 10 C5    LDX    #$10C5
E3DB: 8D B8       BSR    io_merge_nibbles_e395
E3DD: 33 41       LEAU   $1,U
E3DF: 8D B4       BSR    io_merge_nibbles_e395
E3E1: A6 41       LDA    $1,U
E3E3: 97 C4       STA    <$C4                   ; <$C4=DSW0 / service bits
E3E5: 39          RTS

;----------------------------------------------------------------------------
; TASK (slot 1 at power up): I/O chip test ('OK' on screen), read the dips,
; settings screen, sound test / crosshatch while the service switch is on,
; then JMP $C000 (attract).
;----------------------------------------------------------------------------
task_power_up_e3e6:
E3E6: CE 48 08    LDU    #$4808
E3E9: BD E4 A3    JSR    io_set_test_mode_e4a3
E3EC: CE 48 18    LDU    #$4818
E3EF: BD E4 A3    JSR    io_set_test_mode_e4a3
E3F2: BD E2 B4    JSR    task_yield_e2b4
E3F5: CC 4F 4B    LDD    #$4F4B
E3F8: B7 02 64    STA    $0264
E3FB: F7 02 44    STB    $0244
E3FE: CE 48 08    LDU    #$4808
E401: 8E E4 B0    LDX    #$E4B0
E404: 10 8E 00 03 LDY    #$0003
E408: BD EE BA    JSR    memcpy_eeba
E40B: 86 09       LDA    #$09
E40D: B7 48 18    STA    namco_io2_mode_4818
E410: BD E2 B4    JSR    task_yield_e2b4
E413: BD E4 B6    JSR    decode_dip_switches_e4b6
E416: BD E5 97    JSR    draw_settings_screen_e597
E419: CE 02 E8    LDU    #$02E8
E41C: DC C8       LDD    <$C8
E41E: BD E5 B6    JSR    print_coinage_e5b6
E421: CE 02 EA    LDU    #$02EA
E424: DC CA       LDD    <$CA
E426: BD E5 B6    JSR    print_coinage_e5b6
E429: 96 D0       LDA    <$D0                   ; <$D0=lives setting
E42B: 8B 30       ADDA   #$30
E42D: B7 02 0C    STA    $020C
E430: 96 D1       LDA    <$D1                   ; <$D1=difficulty rank setting
E432: BD FE 36    JSR    bcd_low_to_ascii_fe36
E435: B7 02 4E    STA    $024E
E438: BD E6 95    JSR    service_sound_test_e695
E43B: BD E5 D9    JSR    print_bonus_life_e5d9
E43E: BD E6 5C    JSR    print_freeze_setting_e65c
E441: BD E6 76    JSR    print_demo_sound_e676
E444: BD FE C6    JSR    service_easter_egg_fec6
E447: 96 DC       LDA    <$DC
E449: 84 C0       ANDA   #$C0
E44B: 27 02       BEQ    $E44F
E44D: 86 01       LDA    #$01
E44F: 97 84       STA    <$84                   ; <$84=current player (0/1)
E451: 96 C4       LDA    <$C4                   ; <$C4=DSW0 / service bits
E453: 84 08       ANDA   #$08
E455: 27 01       BEQ    $E458
E457: 39          RTS
E458: 97 84       STA    <$84                   ; <$84=current player (0/1)
E45A: CE 40 40    LDU    #$4040
E45D: 8E 00 20    LDX    #$0020
E460: BD EE B1    JSR    fill_words_eeb1
E463: CE 48 08    LDU    #$4808
E466: 86 02       LDA    #$02
E468: A7 C0       STA    ,U+
E46A: 8E 10 C8    LDX    #$10C8
E46D: C6 07       LDB    #$07
E46F: A6 80       LDA    ,X+
E471: A7 C0       STA    ,U+
E473: 5A          DECB
E474: 26 F9       BNE    $E46F
E476: BD E6 F2    JSR    draw_crosshatch_e6f2
E479: CC 00 78    LDD    #$0078
E47C: BD E2 BB    JSR    task_wait_init_e2bb
E47F: BD E2 C4    JSR    task_wait_e2c4
E482: 96 C4       LDA    <$C4                   ; <$C4=DSW0 / service bits
E484: 84 08       ANDA   #$08
E486: 27 01       BEQ    $E489
E488: 39          RTS
E489: 97 86       STA    <$86                   ; <$86=player-up blink control
E48B: 4C          INCA
E48C: 97 E8       STA    <$E8                   ; <$E8=service mode flag
E48E: CE 48 08    LDU    #$4808
E491: 86 04       LDA    #$04
E493: A7 C4       STA    ,U
E495: 86 01       LDA    #$01
E497: A7 41       STA    $1,U
E499: 96 EA       LDA    <$EA
E49B: A7 42       STA    $2,U
E49D: BD E2 B4    JSR    task_yield_e2b4
E4A0: 7E C0 00    JMP    cold_start_attract_c000

io_set_test_mode_e4a3:
E4A3: 86 08       LDA    #$08
E4A5: A7 C0       STA    ,U+
E4A7: CC 0F 07    LDD    #$0F07
E4AA: A7 C0       STA    ,U+
E4AC: 5A          DECB
E4AD: 26 FB       BNE    $E4AA
E4AF: 39          RTS

;----------------------------------------------------------------------------
; Decode the dip switches into coinage, lives, bonus life, rank, demo sound, freeze.
;----------------------------------------------------------------------------
decode_dip_switches_e4b6:
E4B6: 96 C4       LDA    <$C4                   ; <$C4=DSW0 / service bits
E4B8: 84 04       ANDA   #$04
E4BA: 44          LSRA
E4BB: 44          LSRA
E4BC: 97 83       STA    <$83                   ; <$83=cocktail cabinet
E4BE: 96 C5       LDA    <$C5                   ; <$C5=DSW2 (coin A, bonus, lives)
E4C0: 84 07       ANDA   #$07
E4C2: 48          ASLA
E4C3: 8E E5 2B    LDX    #$E52B
E4C6: EC 86       LDD    A,X
E4C8: DD C8       STD    <$C8
E4CA: 96 C5       LDA    <$C5                   ; <$C5=DSW2 (coin A, bonus, lives)
E4CC: 49          ROLA
E4CD: 49          ROLA
E4CE: 49          ROLA
E4CF: 84 03       ANDA   #$03
E4D1: 8E E5 93    LDX    #$E593
E4D4: A6 86       LDA    A,X
E4D6: 97 D0       STA    <$D0                   ; <$D0=lives setting
E4D8: 8E E5 43    LDX    #$E543
E4DB: 81 05       CMPA   #$05
E4DD: 26 03       BNE    $E4E2
E4DF: 8E E5 47    LDX    #$E547
E4E2: D6 C5       LDB    <$C5                   ; <$C5=DSW2 (coin A, bonus, lives)
E4E4: C4 38       ANDB   #$38
E4E6: 3A          ABX
E4E7: EE 81       LDU    ,X++
E4E9: DF D4       STU    <$D4                   ; <$D4=first extra life (BCD)
E4EB: DF 87       STU    <$87
E4ED: EE 84       LDU    ,X
E4EF: DF D6       STU    <$D6                   ; <$D6=extra life every (BCD)
E4F1: 54          LSRB
E4F2: 54          LSRB
E4F3: 81 05       CMPA   #$05
E4F5: 26 01       BNE    $E4F8
E4F7: 5C          INCB
E4F8: 8E E5 83    LDX    #$E583
E4FB: A6 85       LDA    B,X
E4FD: 97 CF       STA    <$CF                   ; <$CF=bonus life setting
E4FF: 96 C6       LDA    <$C6                   ; <$C6=DSW1 (rank, coin B, demo sound, freeze)
E501: 84 0F       ANDA   #$0F
E503: 97 D1       STA    <$D1                   ; <$D1=difficulty rank setting
E505: 96 C6       LDA    <$C6                   ; <$C6=DSW1 (rank, coin B, demo sound, freeze)
E507: 84 30       ANDA   #$30
E509: 44          LSRA
E50A: 44          LSRA
E50B: 44          LSRA
E50C: 8E E5 3B    LDX    #$E53B
E50F: EC 86       LDD    A,X
E511: DD CA       STD    <$CA
E513: 96 C6       LDA    <$C6                   ; <$C6=DSW1 (rank, coin B, demo sound, freeze)
E515: 43          COMA
E516: 49          ROLA
E517: 49          ROLA
E518: 49          ROLA
E519: 84 01       ANDA   #$01
E51B: 97 D3       STA    <$D3                   ; <$D3=demo sounds
E51D: CC 01 01    LDD    #$0101
E520: DD CC       STD    <$CC
E522: 86 00       LDA    #$00
E524: 97 CE       STA    <$CE
E526: 86 01       LDA    #$01
E528: 97 EA       STA    <$EA
E52A: 39          RTS

draw_settings_screen_e597:
E597: CE 02 E6    LDU    #$02E6
E59A: 96 83       LDA    <$83                   ; <$83=cocktail cabinet
E59C: 27 0C       BEQ    $E5AA
E59E: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E5A1-$E5A9 (bytes not in this listing, ends with $00), then continues after it

E5AA: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E5AD-$E5B5 (bytes not in this listing, ends with $00), then continues after it

print_coinage_e5b6:
E5B6: 8B 30       ADDA   #$30
E5B8: A7 C4       STA    ,U
E5BA: 81 32       CMPA   #$32
E5BC: 86 20       LDA    #$20
E5BE: 25 02       BCS    $E5C2
E5C0: 86 53       LDA    #$53
E5C2: A7 C9 FF 40 STA    -$00C0,U
E5C6: CB 30       ADDB   #$30
E5C8: E7 C9 FF 00 STB    -$0100,U
E5CC: C1 32       CMPB   #$32
E5CE: C6 20       LDB    #$20
E5D0: 25 02       BCS    $E5D4
E5D2: C6 53       LDB    #$53
E5D4: E7 C9 FE 00 STB    -$0200,U
E5D8: 39          RTS

print_bonus_life_e5d9:
E5D9: CE 03 72    LDU    #$0372
E5DC: 96 CF       LDA    <$CF                   ; <$CF=bonus life setting
E5DE: 26 27       BNE    $E607
E5E0: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E5E3-$E5FB (bytes not in this listing, ends with $00), then continues after it

print_bonus_life_tail_e5fc:
E5FC: 8D 03       BSR    clear_text_e601
E5FE: CE 03 76    LDU    #$0376

clear_text_e601:
E601: CC 20 15    LDD    #$2015
E604: 7E FE 0F    JMP    fill_row_fe0f
E607: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E60A-$E61B (bytes not in this listing, ends with $00), then continues after it

E61C: 96 CF       LDA    <$CF                   ; <$CF=bonus life setting
E61E: 4A          DECA
E61F: 27 DB       BEQ    print_bonus_life_tail_e5fc
E621: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E624-$E62F (bytes not in this listing, ends with $00), then continues after it

E630: CE 03 76    LDU    #$0376
E633: 96 CF       LDA    <$CF                   ; <$CF=bonus life setting
E635: 4C          INCA
E636: 26 C9       BNE    clear_text_e601
E638: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E63B-$E645 (bytes not in this listing, ends with $00), then continues after it

E646: 10 D6 10    LDB    <$10                   ; <$10=bonus item type of the level ; page-2 prefix $10 + page-1 opcode: a real 6809 ignores the $10 (check this byte in the ROM, may belong to the string before)
E649: 8E 03 02    LDX    #$0302
E64C: BD FE 1C    JSR    print_bcd_fe1c
E64F: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E652-$E65B (bytes not in this listing, ends with $00), then continues after it

print_freeze_setting_e65c:
E65C: CE 02 F8    LDU    #$02F8
E65F: 96 D2       LDA    <$D2
E661: 27 0D       BEQ    $E670
E663: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E666-$E66F (bytes not in this listing, ends with $00), then continues after it

E670: CC 20 08    LDD    #$2008
E673: 7E FE 0F    JMP    fill_row_fe0f

print_demo_sound_e676:
E676: CE 02 FA    LDU    #$02FA
E679: 96 D3       LDA    <$D3                   ; <$D3=demo sounds
E67B: 27 12       BEQ    $E68F
E67D: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E680-$E68D (bytes not in this listing, ends with $00), then continues after it

E68E: 39          RTS
E68F: CC 20 0D    LDD    #$200D
E692: 7E FE 0F    JMP    fill_row_fe0f

;----------------------------------------------------------------------------
; Service mode sound test: joystick selects a sound (<$E9) written to $4040+n.
;----------------------------------------------------------------------------
service_sound_test_e695:
E695: CE 10 DC    LDU    #$10DC
E698: A6 C2       LDA    ,-U
E69A: AA C2       ORA    ,-U
E69C: 43          COMA
E69D: A4 C2       ANDA   ,-U
E69F: A4 C2       ANDA   ,-U
E6A1: 27 1D       BEQ    $E6C0
E6A3: 85 A0       BITA   #$A0
E6A5: 27 02       BEQ    $E6A9
E6A7: 8D 26       BSR    service_sound_select_e6cf
E6A9: CE 02 30    LDU    #$0230
E6AC: 8E 10 E9    LDX    #$10E9
E6AF: 10 8E 00 01 LDY    #$0001
E6B3: BD FE 1C    JSR    print_bcd_fe1c
E6B6: D6 E9       LDB    <$E9                   ; <$E9=sound test index
E6B8: 8E 40 40    LDX    #$4040
E6BB: 86 01       LDA    #$01
E6BD: A7 85       STA    B,X
E6BF: 39          RTS
E6C0: CE 10 E0    LDU    #$10E0
E6C3: A6 C2       LDA    ,-U
E6C5: AA C2       ORA    ,-U
E6C7: 43          COMA
E6C8: A4 C2       ANDA   ,-U
E6CA: A4 C2       ANDA   ,-U
E6CC: 26 DB       BNE    $E6A9
E6CE: 39          RTS

service_sound_select_e6cf:
E6CF: 2B 0C       BMI    $E6DD
E6D1: D6 E9       LDB    <$E9                   ; <$E9=sound test index
E6D3: 96 E9       LDA    <$E9                   ; <$E9=sound test index
E6D5: 4C          INCA
E6D6: 81 17       CMPA   #$17
E6D8: 26 0C       BNE    $E6E6
E6DA: 4F          CLRA
E6DB: 20 09       BRA    $E6E6
E6DD: D6 E9       LDB    <$E9                   ; <$E9=sound test index
E6DF: 96 E9       LDA    <$E9                   ; <$E9=sound test index
E6E1: 26 02       BNE    $E6E5
E6E3: 86 17       LDA    #$17
E6E5: 4A          DECA
E6E6: 97 E9       STA    <$E9                   ; <$E9=sound test index
E6E8: 8E 40 40    LDX    #$4040
E6EB: 3A          ABX
E6EC: 6F 84       CLR    ,X
E6EE: 6F 88 20    CLR    $20,X
E6F1: 39          RTS

;----------------------------------------------------------------------------
; Service mode crosshatch pattern.
;----------------------------------------------------------------------------
draw_crosshatch_e6f2:
E6F2: CE 00 00    LDU    #$0000
E6F5: 8D 0F       BSR    crosshatch_row_e706
E6F7: C6 0E       LDB    #$0E
E6F9: 8E 3D 3F    LDX    #$3D3F
E6FC: 8D 10       BSR    fill_16_words_e70e
E6FE: 8E 3C 3E    LDX    #$3C3E
E701: 8D 0B       BSR    fill_16_words_e70e
E703: 5A          DECB
E704: 26 F3       BNE    $E6F9

crosshatch_row_e706:
E706: 8E 3D 3C    LDX    #$3D3C
E709: 8D 03       BSR    fill_16_words_e70e
E70B: 8E 3F 3E    LDX    #$3F3E

fill_16_words_e70e:
E70E: 86 10       LDA    #$10
E710: AF C1       STX    ,U++
E712: 4A          DECA
E713: 26 FB       BNE    $E710
E715: 39          RTS

;----------------------------------------------------------------------------
; TASK (slot 1) : a credit was inserted (set by check_coin_start_e275).
; Anti-tampering: checks 'NAMCO' in the default high score table
; ($EB58..): if modified, the task stops here forever. Then 'PUSH START'.
;----------------------------------------------------------------------------
task_credit_inserted_e716:
E716: 0F AB       CLR    <$AB                   ; <$AB=input mode 0=live 1=record 2=demo playback
E718: BD E2 9E    JSR    enable_object_tasks_e29e
E71B: BD E2 B4    JSR    task_yield_e2b4
; copyright tampering protection check, when inserting a credit
E71E: B6 EB 58    LDA    $EB58
E721: F6 EB 5C    LDB    $EB5C
E724: 83 4E 41    SUBD   #$4E41
E727: 27 01       BEQ    $E72A
; namco copyright has been tampered with: make game fail
E729: 39          RTS
; another copyright tampering protection check
E72A: B6 EB 60    LDA    $EB60
E72D: F6 EB 64    LDB    $EB64
E730: 83 4D 43    SUBD   #$4D43
E733: 27 01       BEQ    $E736
E735: 39          RTS
; another tampering protection check
E736: B6 EB 68    LDA    $EB68
E739: 80 4F       SUBA   #$4F
E73B: 27 01       BEQ    $E73E
E73D: 39          RTS
E73E: 7F 48 09    CLR    $4809
E741: 86 04       LDA    #$04
E743: 97 14       STA    <$14                   ; <$14=maze colour
E745: BD EE 06    JSR    clear_screen_and_status_ee06
E748: CE 02 E8    LDU    #$02E8
E74B: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E74E-$E762 (bytes not in this listing, ends with $00), then continues after it

;----------------------------------------------------------------------------
; Wait for START 1 / START 2 ('1 PLAYER ONLY' / '1 OR 2 PLAYERS').
;----------------------------------------------------------------------------
wait_start_button_e763:
E763: BD C1 03    JSR    print_copyright_c103
E766: BD E2 B4    JSR    task_yield_e2b4
E769: BD FB 90    JSR    random_fb90
E76C: 96 C0       LDA    <$C0                   ; <$C0=credits
E76E: 90 C1       SUBA   <$C1                   ; <$C1=credits needed / play
E770: 25 2E       BCS    start_game_e7a0
E772: CE 02 AB    LDU    #$02AB
E775: 96 C0       LDA    <$C0                   ; <$C0=credits
E777: 4A          DECA
E778: 26 13       BNE    $E78D
E77A: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E77D-$E787 (bytes not in this listing, ends with $00), then continues after it

;	dc.b	$4C,$59,$20,$00                           ; end of the inline string ('LY ' + $00)
E78C: 39          RTS
E78D: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E790-$E79F (bytes not in this listing, ends with $00), then continues after it

;----------------------------------------------------------------------------
; Start the game: credits -= 1 or 2, player data init, level init, start music.
;----------------------------------------------------------------------------
start_game_e7a0:
E7A0: 86 99       LDA    #$99
E7A2: 90 C0       SUBA   <$C0                   ; <$C0=credits
E7A4: 9B C1       ADDA   <$C1                   ; <$C1=credits needed / play
E7A6: 19          DAA
E7A7: 97 82       STA    <$82                   ; <$82=2-player game flag
E7A9: 4F          CLRA
E7AA: 97 84       STA    <$84                   ; <$84=current player (0/1)
E7AC: 97 C7       STA    <$C7                   ; <$C7=attract flag
E7AE: 97 06       STA    <$06                   ; <$06=extra lives awarded
E7B0: CE 10 00    LDU    #$1000
E7B3: 8E 00 40    LDX    #$0040
E7B6: BD EE B1    JSR    fill_words_eeb1
E7B9: 4C          INCA
E7BA: B7 48 09    STA    $4809
E7BD: BD CD 45    JSR    new_game_level_init_cd45
E7C0: DC D4       LDD    <$D4                   ; <$D4=first extra life (BCD)
E7C2: DD 04       STD    <$04                   ; <$04=next extra-life score
E7C4: 96 D0       LDA    <$D0                   ; <$D0=lives setting
E7C6: 97 07       STA    <$07                   ; <$07=lives left
E7C8: BD E2 9E    JSR    enable_object_tasks_e29e
E7CB: BD E2 B4    JSR    task_yield_e2b4
E7CE: 86 01       LDA    #$01
E7D0: B7 40 41    STA    $4041                  ; SOUND: start music
E7D3: BD E9 C6    JSR    draw_round_screen_e9c6
E7D6: CC 00 B4    LDD    #$00B4
E7D9: BD E2 BB    JSR    task_wait_init_e2bb
E7DC: BD E2 C4    JSR    task_wait_e2c4
E7DF: BD EA 33    JSR    init_maze_objects_ea33
E7E2: 96 82       LDA    <$82                   ; <$82=2-player game flag
E7E4: 27 0D       BEQ    $E7F3
E7E6: 8E 10 00    LDX    #$1000
E7E9: CE 10 40    LDU    #$1040
E7EC: 10 8E 00 20 LDY    #$0020
E7F0: BD EE BA    JSR    memcpy_eeba
E7F3: 86 01       LDA    #$01
E7F5: 97 86       STA    <$86                   ; <$86=player-up blink control

;----------------------------------------------------------------------------
; Start of a player's turn ('PLAYER 1/2', 'READY').
;----------------------------------------------------------------------------
start_player_turn_e7f7:
E7F7: BD CD C5    JSR    load_level_params_cdc5
E7FA: BD EB 1D    JSR    print_player_up_eb1d
E7FD: CE 02 4F    LDU    #$024F
E800: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E803-$E80D (bytes not in this listing, ends with $00), then continues after it

E80E: BD E2 BB    JSR    task_wait_init_e2bb
E811: BD E2 C4    JSR    task_wait_e2c4
E814: BD EB 32    JSR    clear_player_up_eb32
E817: CE 02 4F    LDU    #$024F
E81A: CC 20 07    LDD    #$2007
E81D: BD FE 0F    JSR    fill_row_fe0f
E820: 0A 07       DEC    <$07                   ; <$07=lives left
E822: BD EE 09    JSR    draw_lives_ee09

;----------------------------------------------------------------------------
; Start a level: maze, objects, Pac-Man and ghosts.
;----------------------------------------------------------------------------
start_level_e825:
E825: 96 96       LDA    <$96                   ; <$96=bonus stage flag
E827: 27 0D       BEQ    $E836
E829: CC 01 06    LDD    #$0106
E82C: DD 8C       STD    <$8C                   ; <$8C=bonus stage timer on
E82E: CC 20 00    LDD    #$2000
E831: DD 8E       STD    <$8E                   ; <$8E=bonus stage time (BCD)
E833: BD E9 1F    JSR    draw_bonus_stage_timer_e91f
E836: CC 00 00    LDD    #$0000
E839: DD 92       STD    <$92                   ; <$92=frames since level start
E83B: BD F5 08    JSR    pacman_start_f508
E83E: BD F7 70    JSR    ghosts_start_f770
E841: BD E2 B4    JSR    task_yield_e2b4

;----------------------------------------------------------------------------
; GAME PLAY LOOP (slot 1, one pass per frame): counts the frames of the
; level and checks the end of the level (<$90 fruits + <$91 pellets = 0).
; The real work is done by the objects (slot 2).
;----------------------------------------------------------------------------
game_play_loop_e844:
E844: 96 96       LDA    <$96                   ; <$96=bonus stage flag
E846: 26 7D       BNE    bonus_stage_loop_e8c5
E848: DC 92       LDD    <$92                   ; <$92=frames since level start
E84A: C3 00 01    ADDD   #$0001
E84D: 25 02       BCS    $E851
E84F: DD 92       STD    <$92                   ; <$92=frames since level start
E851: 96 90       LDA    <$90                   ; <$90=fruits left
E853: 9B 91       ADDA   <$91                   ; <$91=power pellets left
E855: 27 01       BEQ    level_cleared_e858
E857: 39          RTS

;----------------------------------------------------------------------------
; Level cleared: stop objects, flash the maze, cut-scene check, next level.
;----------------------------------------------------------------------------
level_cleared_e858:
E858: CC F1 01    LDD    #$f101                 ; [function_address] ; -> runner_draw_sprite_f101
E85B: FD 16 34    STD    $1634
E85E: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
E861: BD F7 8D    JSR    set_ghosts_runner_f78d
E864: CC 00 1E    LDD    #$001E
E867: BD E2 BB    JSR    task_wait_init_e2bb
E86A: BD E2 C4    JSR    task_wait_e2c4
E86D: BD E2 9E    JSR    enable_object_tasks_e29e
E870: 86 01       LDA    #$01
E872: B7 40 42    STA    $4042                  ; SOUND: level clear
E875: CC 00 80    LDD    #$0080
E878: BD E2 BB    JSR    task_wait_init_e2bb
E87B: BD EA 48    JSR    maze_flash_ea48
E87E: BD E2 C4    JSR    task_wait_e2c4
E881: CC 00 40    LDD    #$0040
E884: BD E2 BB    JSR    task_wait_init_e2bb
E887: BD E2 C4    JSR    task_wait_e2c4
E88A: BD C7 5A    JSR    intermission_check_c75a
E88D: BD CD C1    JSR    next_level_cdc1
E890: BD E9 C6    JSR    draw_round_screen_e9c6
E893: BD E2 BB    JSR    task_wait_init_e2bb
E896: BD E2 C4    JSR    task_wait_e2c4
E899: BD EA 33    JSR    init_maze_objects_ea33
E89C: BD EB 1D    JSR    print_player_up_eb1d
E89F: CE 02 4F    LDU    #$024F
E8A2: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E8A5-$E8AF (bytes not in this listing, ends with $00), then continues after it

E8B0: BD E2 BB    JSR    task_wait_init_e2bb
E8B3: BD E2 C4    JSR    task_wait_e2c4
E8B6: BD EB 32    JSR    clear_player_up_eb32
E8B9: CE 02 4F    LDU    #$024F
E8BC: CC 20 07    LDD    #$2007
E8BF: BD FE 0F    JSR    fill_row_fe0f
E8C2: 7E E8 25    JMP    start_level_e825

;----------------------------------------------------------------------------
; Bonus stage loop (<$96): time counter, end when everything is eaten or the time is out.
;----------------------------------------------------------------------------
bonus_stage_loop_e8c5:
E8C5: 96 90       LDA    <$90                   ; <$90=fruits left
E8C7: 9B 91       ADDA   <$91                   ; <$91=power pellets left
E8C9: 26 2F       BNE    $E8FA
E8CB: BD E2 9E    JSR    enable_object_tasks_e29e
E8CE: CE 02 4B    LDU    #$024B
E8D1: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E8D4-$E8DF (bytes not in this listing, ends with $00), then continues after it

E8E0: CC 00 1E    LDD    #$001E
E8E3: BD E2 BB    JSR    task_wait_init_e2bb
E8E6: BD E2 C4    JSR    task_wait_e2c4
E8E9: 96 8D       LDA    <$8D                   ; <$8D=bonus stage timer sub-count
E8EB: 81 06       CMPA   #$06
E8ED: 26 0B       BNE    $E8FA
E8EF: CC 00 10    LDD    #$0010
E8F2: BD FD 6B    JSR    add_score_fd6b
E8F5: 86 01       LDA    #$01
E8F7: B7 40 56    STA    $4056                  ; SOUND: bonus stage time bonus
E8FA: 8D 07       BSR    bonus_stage_timer_e903
E8FC: DC 8E       LDD    <$8E                   ; <$8E=bonus stage time (BCD)
E8FE: 10 27 FF 56 LBEQ   level_cleared_e858
E902: 39          RTS

bonus_stage_timer_e903:
E903: 96 8C       LDA    <$8C                   ; <$8C=bonus stage timer on
E905: 26 01       BNE    $E908
E907: 39          RTS
E908: 0A 8D       DEC    <$8D                   ; <$8D=bonus stage timer sub-count
E90A: 27 01       BEQ    $E90D
E90C: 39          RTS
E90D: 86 06       LDA    #$06
E90F: 97 8D       STA    <$8D                   ; <$8D=bonus stage timer sub-count
E911: 96 8F       LDA    <$8F                   ; <$8F=bonus stage time lo
E913: 8B 90       ADDA   #$90
E915: 19          DAA
E916: 97 8F       STA    <$8F                   ; <$8F=bonus stage time lo
E918: 96 8E       LDA    <$8E                   ; <$8E=bonus stage time (BCD)
E91A: 89 99       ADCA   #$99
E91C: 19          DAA
E91D: 97 8E       STA    <$8E                   ; <$8E=bonus stage time (BCD)

draw_bonus_stage_timer_e91f:
E91F: CE 02 4A    LDU    #$024A
E922: 8E 10 8E    LDX    #$108E
E925: 10 8E 02 02 LDY    #$0202
E929: BD FE 1C    JSR    print_bcd_fe1c
E92C: 86 30       LDA    #$30
E92E: A7 C4       STA    ,U
E930: 39          RTS

draw_bonus_stage_screen_e931:
E931: 96 CF       LDA    <$CF                   ; <$CF=bonus life setting
E933: 26 01       BNE    $E936
E935: 39          RTS
E936: CE 03 AF    LDU    #$03AF
E939: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E93C-$E94D (bytes not in this listing, ends with $00), then continues after it

E94E: 10 D4 8D    ANDB   <$8D                   ; <$8D=bonus stage timer sub-count ; page-2 prefix $10 + page-1 opcode: a real 6809 ignores the $10 (check this byte in the ROM, may belong to the string before)
E951: 4F          CLRA
E952: CE 16 30    LDU    #$1630
E955: CC 98 7C    LDD    #$987C
E958: 8D 5B       BSR    set_static_sprite_e9b5
E95A: 96 CF       LDA    <$CF                   ; <$CF=bonus life setting
E95C: 4A          DECA
E95D: 26 01       BNE    $E960
E95F: 39          RTS
E960: CE 03 B2    LDU    #$03B2
E963: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E966-$E97E (bytes not in this listing, ends with $00), then continues after it

E97F: 8D 34       BSR    set_static_sprite_e9b5
E981: CE 03 76    LDU    #$0376
E984: 96 CF       LDA    <$CF                   ; <$CF=bonus life setting
E986: 4C          INCA
E987: 27 01       BEQ    $E98A
E989: 39          RTS
E98A: CE 03 55    LDU    #$0355
E98D: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E990-$E99E (bytes not in this listing, ends with $00), then continues after it

E99F: 10 D6 10    LDB    <$10                   ; <$10=bonus item type of the level ; page-2 prefix $10 + page-1 opcode: a real 6809 ignores the $10 (check this byte in the ROM, may belong to the string before)
E9A2: 8E 03 02    LDX    #$0302
E9A5: BD FE 1C    JSR    print_bcd_fe1c
E9A8: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E9AB-$E9B4 (bytes not in this listing, ends with $00), then continues after it

set_static_sprite_e9b5:
E9B5: ED 4C       STD    $C,U
E9B7: 86 02       LDA    #$02
E9B9: A7 49       STA    $9,U
E9BB: CC 01 01    LDD    #$0101
E9BE: ED 4A       STD    $A,U
E9C0: CC F1 01    LDD    #$f101                 ; [function_address] ; -> runner_draw_sprite_f101
E9C3: ED 44       STD    $4,U
E9C5: 39          RTS

;----------------------------------------------------------------------------
; Round screen: clear, bonus item icon, round number.
;----------------------------------------------------------------------------
draw_round_screen_e9c6:
E9C6: BD EE 06    JSR    clear_screen_and_status_ee06
E9C9: CE 09 F0    LDU    #$09F0
E9CC: CC 98 94    LDD    #$9894
E9CF: ED 4C       STD    $C,U
E9D1: 4F          CLRA
E9D2: D6 10       LDB    <$10                   ; <$10=bonus item type of the level
E9D4: CB 44       ADDB   #$44
E9D6: ED 49       STD    $9,U
E9D8: 96 10       LDA    <$10                   ; <$10=bonus item type of the level
E9DA: 8B 10       ADDA   #$10
E9DC: A7 4B       STA    $B,U
E9DE: CC F1 01    LDD    #$f101                 ; [function_address] ; -> runner_draw_sprite_f101
E9E1: ED 44       STD    $4,U
E9E3: 8E 10 13    LDX    #$1013
E9E6: CE 02 32    LDU    #$0232
E9E9: 10 8E 01 01 LDY    #$0101
E9ED: BD FE 1C    JSR    print_bcd_fe1c
E9F0: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $E9F3-$E9FC (bytes not in this listing, ends with $00), then continues after it

E9FD: CE 02 6E    LDU    #$026E
EA00: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $EA03-$EA09 (bytes not in this listing, ends with $00), then continues after it

EA0A: 8E 10 03    LDX    #$1003
EA0D: 10 8E 01 01 LDY    #$0101
EA11: BD FE 1C    JSR    print_bcd_fe1c
EA14: CC 00 78    LDD    #$0078
EA17: 39          RTS

function_ea18:
EA18: 86 01       LDA    #$01
EA1A: B7 40 52    STA    $4052                  ; SOUND: bonus stage
EA1D: CE 02 8E    LDU    #$028E
EA20: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $EA23-$EA2D (bytes not in this listing, ends with $00), then continues after it
; seems unreached
EA2F: CC 00 78    LDD    #$0078                 ; real instruction (was mis-disassembled)
EA32: 39          RTS

;----------------------------------------------------------------------------
; Create all the maze objects: maze, doors, keys, fruits, power pellets, Pac-Man, ghosts.
;----------------------------------------------------------------------------
init_maze_objects_ea33:
EA33: BD EE 65    JSR    draw_maze_ee65
EA36: BD EF C0    JSR    doors_set_all_efc0
EA39: BD F1 8F    JSR    keys_set_all_f18f
EA3C: BD F3 33    JSR    fruits_set_all_f333
EA3F: BD F4 1E    JSR    pellets_set_all_f41e
EA42: BD F5 34    JSR    pacman_remove_f534
EA45: 7E F7 36    JMP    ghosts_init_f736

maze_flash_ea48:
EA48: E6 43       LDB    $3,U
EA4A: C5 07       BITB   #$07
EA4C: 27 01       BEQ    $EA4F
EA4E: 39          RTS
EA4F: 86 0B       LDA    #$0B
EA51: C4 08       ANDB   #$08
EA53: 27 02       BEQ    $EA57
EA55: 96 14       LDA    <$14                   ; <$14=maze colour
EA57: CE 04 40    LDU    #$0440
EA5A: 8E 01 C0    LDX    #$01C0
EA5D: 7E EE B1    JMP    fill_words_eeb1

;----------------------------------------------------------------------------
; TASK (slot 1) : Pac-Man died (set by pacman_death_task_f666). Game over
; check, player switch in a 2 player game, re-create the objects.
;----------------------------------------------------------------------------
pacman_died_ea60:
EA60: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
EA62: 10 27 DA 4B LBEQ   demo_game_end_c4b1
EA66: 96 90       LDA    <$90                   ; <$90=fruits left
EA68: 9B 91       ADDA   <$91                   ; <$91=power pellets left
EA6A: 10 27 FD EA LBEQ   level_cleared_e858
EA6E: BD CD B3    JSR    auto_rank_on_death_cdb3
EA71: BD E2 9E    JSR    enable_object_tasks_e29e
EA74: BD E2 B4    JSR    task_yield_e2b4
EA77: 96 82       LDA    <$82                   ; <$82=2-player game flag
EA79: 26 18       BNE    $EA93
EA7B: 96 07       LDA    <$07                   ; <$07=lives left
EA7D: 26 1E       BNE    $EA9D
EA7F: 0F 86       CLR    <$86                   ; <$86=player-up blink control
EA81: BD EB 07    JSR    print_game_over_eb07
EA84: CC 00 F0    LDD    #$00F0
EA87: BD E2 BB    JSR    task_wait_init_e2bb
EA8A: BD E2 C4    JSR    task_wait_e2c4
EA8D: BD EB 6C    JSR    check_hiscore_entry_eb6c
EA90: 7E C0 03    JMP    attract_loop_c003
EA93: 96 07       LDA    <$07                   ; <$07=lives left
EA95: 27 27       BEQ    $EABE
EA97: 96 47       LDA    <$47
EA99: 27 02       BEQ    $EA9D
EA9B: 8D 4B       BSR    swap_player_data_eae8
EA9D: BD E9 C6    JSR    draw_round_screen_e9c6
EAA0: BD E2 BB    JSR    task_wait_init_e2bb
EAA3: BD E2 C4    JSR    task_wait_e2c4
EAA6: BD EE 65    JSR    draw_maze_ee65
EAA9: BD EF AA    JSR    doors_init_efaa
EAAC: BD F1 65    JSR    keys_init_f165
EAAF: BD F3 05    JSR    fruits_init_f305
EAB2: BD F3 F0    JSR    pellets_init_f3f0
EAB5: BD F5 34    JSR    pacman_remove_f534
EAB8: BD F7 36    JSR    ghosts_init_f736
EABB: 7E E7 F7    JMP    start_player_turn_e7f7
EABE: BD EB 05    JSR    game_over_eb05
EAC1: CC 00 F0    LDD    #$00F0
EAC4: BD E2 BB    JSR    task_wait_init_e2bb
EAC7: BD E2 C4    JSR    task_wait_e2c4
EACA: BD EB 6C    JSR    check_hiscore_entry_eb6c
EACD: 96 47       LDA    <$47
EACF: 26 CA       BNE    $EA9B
EAD1: BD EB 32    JSR    clear_player_up_eb32
EAD4: 0F 86       CLR    <$86                   ; <$86=player-up blink control
EAD6: CC 00 B4    LDD    #$00B4
EAD9: BD E2 BB    JSR    task_wait_init_e2bb
EADC: BD E2 C4    JSR    task_wait_e2c4
EADF: 96 84       LDA    <$84                   ; <$84=current player (0/1)
EAE1: 27 02       BEQ    $EAE5
EAE3: 8D 03       BSR    swap_player_data_eae8
EAE5: 7E C0 03    JMP    attract_loop_c003

;----------------------------------------------------------------------------
; Swap the current player data $1000-$103F with the other player's copy $1040-$107F.
;----------------------------------------------------------------------------
swap_player_data_eae8:
EAE8: 96 84       LDA    <$84                   ; <$84=current player (0/1)
EAEA: 88 01       EORA   #$01
EAEC: 97 84       STA    <$84                   ; <$84=current player (0/1)
EAEE: 8E 10 00    LDX    #$1000
EAF1: CE 10 40    LDU    #$1040
EAF4: 10 8E 00 40 LDY    #$0040
EAF8: A6 84       LDA    ,X
EAFA: E6 C4       LDB    ,U
EAFC: E7 80       STB    ,X+
EAFE: A7 C0       STA    ,U+
EB00: 31 3F       LEAY   -$1,Y
EB02: 26 F4       BNE    $EAF8
EB04: 39          RTS

game_over_eb05:
EB05: 8D 16       BSR    print_player_up_eb1d

print_game_over_eb07:
EB07: 86 01       LDA    #$01
EB09: B7 40 43    STA    $4043                  ; SOUND: game over

print_game_over_text_eb0c:
EB0C: CE 02 8F    LDU    #$028F
EB0F: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $EB12-$EB1A (bytes not in this listing, ends with $00), then continues after it

EB1C: 39          RTS

print_player_up_eb1d:
EB1D: CE 02 6E    LDU    #$026E
EB20: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $EB23-$EB2A (bytes not in this listing, ends with $00), then continues after it

EB2B: 96 84       LDA    <$84                   ; <$84=current player (0/1)
EB2D: 8B 31       ADDA   #$31
EB2F: A7 C4       STA    ,U
EB31: 39          RTS

clear_player_up_eb32:
EB32: CE 02 6E    LDU    #$026E
EB35: CC 20 08    LDD    #$2008
EB38: 7E FE 0F    JMP    fill_row_fe0f

;----------------------------------------------------------------------------
; Default high score table ($1138-$115F, 5 x 8 bytes) from $EB58 (NAMCO...).
;----------------------------------------------------------------------------
init_hiscore_table_eb3b:
EB3B: CE EB 58    LDU    #$EB58
EB3E: 8E 11 38    LDX    #$1138
EB41: DC D4       LDD    <$D4                   ; <$D4=first extra life (BCD)
EB43: ED 81       STD    ,X++
EB45: CC 00 00    LDD    #$0000
EB48: ED 81       STD    ,X++
EB4A: EC C1       LDD    ,U++
EB4C: ED 81       STD    ,X++
EB4E: EC C1       LDD    ,U++
EB50: ED 81       STD    ,X++
EB52: 8C 11 60    CMPX   #$1160
EB55: 26 EA       BNE    $EB41
EB57: 39          RTS

;----------------------------------------------------------------------------
; High score check and name entry (up to $0E10 frames).
;----------------------------------------------------------------------------
check_hiscore_entry_eb6c:
EB6C: CE 10 00    LDU    #$1000
EB6F: 8E 11 38    LDX    #$1138
EB72: EC C4       LDD    ,U
EB74: 10 A3 84    CMPD   ,X
EB77: 26 04       BNE    $EB7D
EB79: A6 42       LDA    $2,U
EB7B: A1 02       CMPA   $2,X
EB7D: 24 08       BCC    $EB87
EB7F: 30 08       LEAX   $8,X
EB81: 8C 11 60    CMPX   #$1160
EB84: 26 EC       BNE    $EB72
EB86: 39          RTS
EB87: 1F 10       TFR    X,D
EB89: C0 38       SUBB   #$38
EB8B: 54          LSRB
EB8C: 54          LSRB
EB8D: D7 E1       STB    <$E1
EB8F: 58          ASLB
EB90: 58          ASLB
EB91: 50          NEGB
EB92: CB 20       ADDB   #$20
EB94: 27 0A       BEQ    $EBA0
EB96: 8E 11 58    LDX    #$1158
EB99: A6 82       LDA    ,-X
EB9B: A7 08       STA    $8,X
EB9D: 5A          DECB
EB9E: 26 F9       BNE    $EB99
EBA0: EC C4       LDD    ,U
EBA2: ED 84       STD    ,X
EBA4: EC 42       LDD    $2,U
EBA6: ED 02       STD    $2,X
EBA8: CC 20 20    LDD    #$2020
EBAB: ED 04       STD    $4,X
EBAD: ED 06       STD    $6,X
EBAF: BD EE 06    JSR    clear_screen_and_status_ee06
EBB2: CE 03 2A    LDU    #$032A
EBB5: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $EBB8-$EBC4 (bytes not in this listing, ends with $00), then continues after it

EBCE: CE 03 0D    LDU    #$030D                 ; real instruction (was mis-disassembled)
EBD1: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $EBD4-$EBE5 (bytes not in this listing, ends with $00), then continues after it


EBE7: CE 03 4F    LDU    #$034F                 ; real instruction (was mis-disassembled)
EBEA: 8E 10 00    LDX    #$1000
EBED: 10 8E 05 03 LDY    #$0503
EBF1: BD FE 1C    JSR    print_bcd_fe1c
EBF4: 86 30       LDA    #$30
EBF6: A7 C4       STA    ,U
EBF8: CE 01 EF    LDU    #$01EF
EBFB: 8E 10 03    LDX    #$1003
EBFE: 10 8E 01 01 LDY    #$0101
EC02: BD FE 1C    JSR    print_bcd_fe1c
EC05: BD EC 50    JSR    draw_hiscore_table_ec50
EC08: 35 06       PULS   D
EC0A: DD E4       STD    <$E4                   ; <$E4=saved return address
EC0C: 0F E0       CLR    <$E0
EC0E: BD ED 30    JSR    name_entry_reset_letter_ed30
EC11: CC 0E 10    LDD    #$0E10
EC14: BD E2 BB    JSR    task_wait_init_e2bb
EC17: BD ED 7E    JSR    name_entry_music_ed7e
EC1A: BD ED 16    JSR    name_entry_blink_ed16
EC1D: BD EC C0    JSR    name_entry_input_ecc0
EC20: DC E6       LDD    <$E6
EC22: 27 09       BEQ    $EC2D
EC24: 96 E0       LDA    <$E0
EC26: 81 A0       CMPA   #$A0
EC28: 27 03       BEQ    $EC2D
EC2A: BD E2 C4    JSR    task_wait_e2c4
EC2D: CC 00 3C    LDD    #$003C
EC30: BD E2 BB    JSR    task_wait_init_e2bb
EC33: BD ED 5D    JSR    name_entry_draw_timer_ed5d
EC36: BD ED 7E    JSR    name_entry_music_ed7e
EC39: BD E2 C4    JSR    task_wait_e2c4
EC3C: BD ED 5D    JSR    name_entry_draw_timer_ed5d
EC3F: FC 40 44    LDD    $4044
EC42: 27 01       BEQ    $EC45
EC44: 39          RTS
EC45: 96 81       LDA    <$81                   ; <$81=frame counter
EC47: 84 10       ANDA   #$10
EC49: 26 01       BNE    $EC4C
EC4B: 39          RTS
EC4C: 6E 9F 10 E4 JMP    [$10E4]

draw_hiscore_table_ec50:
EC50: CE 02 93    LDU    #$0293
EC53: BD EE C7    JSR    print_inline_string_eec7 ; [no_return] ; prints the INLINE string at $EC56-$EC69 (bytes not in this listing, ends with $00), then continues after it

EC6A: CE 03 15    LDU    #$0315
EC6D: C6 05       LDB    #$05
EC6F: A6 80       LDA    ,X+
EC71: A7 C1       STA    ,U++
EC73: 5A          DECB
EC74: 26 F9       BNE    $EC6F
EC76: 33 C8 16    LEAU   $16,U
EC79: 8C EC C0    CMPX   #$ECC0
EC7C: 26 EF       BNE    $EC6D
EC7E: 8E 11 38    LDX    #$1138
EC81: CE 02 D5    LDU    #$02D5
EC84: 10 8E 05 03 LDY    #$0503
EC88: BD FE 1C    JSR    print_bcd_fe1c
EC8B: 86 30       LDA    #$30
EC8D: A7 C4       STA    ,U
EC8F: 33 C8 80    LEAU   -$80,U
EC92: 10 8E 01 01 LDY    #$0101
EC96: BD FE 1C    JSR    print_bcd_fe1c
EC99: EC 81       LDD    ,X++
EC9B: A7 C8 A0    STA    -$60,U
EC9E: E7 C8 80    STB    -$80,U
ECA1: A6 81       LDA    ,X++
ECA3: A7 C9 FF 60 STA    -$00A0,U
ECA7: 33 C9 01 82 LEAU   $0182,U
ECAB: 8C 11 60    CMPX   #$1160
ECAE: 26 D4       BNE    $EC84
ECB0: 39          RTS

ECBB: 31 32       LEAY   -$E,Y
ECBD: 33 34       LEAU   -$C,Y
ECBF: 35 96       PULS   D,X,PC

name_entry_input_ecc0:
ECC0: 96 C2       LDA    <$C2                   ; <$C2=controls read by the I/O chip
ECC2: 85 02       BITA   #$02
ECC4: 26 10       BNE    $ECD6
ECC6: 85 08       BITA   #$08
ECC8: 26 2C       BNE    $ECF6
ECCA: 85 10       BITA   #$10
ECCC: 26 55       BNE    $ED23
ECCE: DC E6       LDD    <$E6
ECD0: 83 00 01    SUBD   #$0001
ECD3: DD E6       STD    <$E6
ECD5: 39          RTS
ECD6: 96 C3       LDA    <$C3                   ; <$C3=previous controls
ECD8: 85 02       BITA   #$02
ECDA: 26 06       BNE    $ECE2
ECDC: 86 20       LDA    #$20
ECDE: 97 E3       STA    <$E3
ECE0: 20 09       BRA    $ECEB
ECE2: 0A E3       DEC    <$E3
ECE4: 27 01       BEQ    $ECE7
ECE6: 39          RTS
ECE7: 86 08       LDA    #$08
ECE9: 97 E3       STA    <$E3
ECEB: 96 E2       LDA    <$E2
ECED: 4C          INCA
ECEE: 81 5B       CMPA   #$5B
ECF0: 26 40       BNE    $ED32
ECF2: 86 40       LDA    #$40
ECF4: 20 3C       BRA    $ED32
ECF6: 96 C3       LDA    <$C3                   ; <$C3=previous controls
ECF8: 85 08       BITA   #$08
ECFA: 26 06       BNE    $ED02
ECFC: 86 20       LDA    #$20
ECFE: 97 E3       STA    <$E3
ED00: 20 09       BRA    $ED0B
ED02: 0A E3       DEC    <$E3
ED04: 27 01       BEQ    $ED07
ED06: 39          RTS
ED07: 86 08       LDA    #$08
ED09: 97 E3       STA    <$E3
ED0B: 96 E2       LDA    <$E2
ED0D: 4A          DECA
ED0E: 81 3F       CMPA   #$3F
ED10: 26 20       BNE    $ED32
ED12: 86 5A       LDA    #$5A
ED14: 20 1C       BRA    $ED32

name_entry_blink_ed16:
ED16: 96 81       LDA    <$81                   ; <$81=frame counter
ED18: 85 0F       BITA   #$0F
ED1A: 27 01       BEQ    $ED1D
ED1C: 39          RTS
ED1D: 84 10       ANDA   #$10
ED1F: 27 2D       BEQ    $ED4E
ED21: 20 29       BRA    name_entry_draw_cursor_ed4c
ED23: 8D 27       BSR    name_entry_draw_cursor_ed4c
ED25: 96 E0       LDA    <$E0
ED27: 80 20       SUBA   #$20
ED29: 97 E0       STA    <$E0
ED2B: 81 A0       CMPA   #$A0
ED2D: 26 01       BNE    name_entry_reset_letter_ed30
ED2F: 39          RTS

name_entry_reset_letter_ed30:
ED30: 86 41       LDA    #$41
ED32: 8E 04 B0    LDX    #$04B0
ED35: 9F E6       STX    <$E6
ED37: 97 E2       STA    <$E2
ED39: 8E 11 3C    LDX    #$113C
ED3C: D6 E0       LDB    <$E0
ED3E: 50          NEGB
ED3F: 58          ASLB
ED40: 58          ASLB
ED41: DA E1       ORB    <$E1
ED43: 59          ROLB
ED44: 59          ROLB
ED45: A7 85       STA    B,X
ED47: 8E 01 2F    LDX    #$012F
ED4A: 8D 05       BSR    name_entry_put_ed51

name_entry_draw_cursor_ed4c:
ED4C: 86 01       LDA    #$01
ED4E: 8E 05 2F    LDX    #$052F

name_entry_put_ed51:
ED51: D6 E0       LDB    <$E0
ED53: A7 85       STA    B,X
ED55: DB E1       ADDB   <$E1
ED57: 30 88 C6    LEAX   -$3A,X
ED5A: A7 85       STA    B,X
ED5C: 39          RTS

name_entry_draw_timer_ed5d:
ED5D: 96 81       LDA    <$81                   ; <$81=frame counter
ED5F: 85 0F       BITA   #$0F
ED61: 27 01       BEQ    $ED64
ED63: 39          RTS
ED64: 84 10       ANDA   #$10
ED66: 27 02       BEQ    $ED6A
ED68: 86 01       LDA    #$01
ED6A: CE 07 4F    LDU    #$074F
ED6D: C6 14       LDB    #$14
ED6F: BD FE 0F    JSR    fill_row_fe0f
ED72: D6 E1       LDB    <$E1
ED74: CE 07 55    LDU    #$0755
ED77: 33 C5       LEAU   B,U
ED79: C6 16       LDB    #$16
ED7B: 7E FE 0F    JMP    fill_row_fe0f

name_entry_music_ed7e:
ED7E: 86 01       LDA    #$01
ED80: D6 E1       LDB    <$E1
ED82: 27 04       BEQ    $ED88
ED84: B7 40 44    STA    $4044                  ; SOUND: name entry
ED87: 39          RTS
ED88: B7 40 45    STA    $4045                  ; SOUND: name entry (1st place)
ED8B: 39          RTS

;----------------------------------------------------------------------------
; Clear the screen: tiles $20, colours (maze colour <$14).
;----------------------------------------------------------------------------
clear_screen_ed8c:
ED8C: 86 20       LDA    #$20
ED8E: CE 00 00    LDU    #$0000
ED91: 8E 02 00    LDX    #$0200
ED94: BD EE B1    JSR    fill_words_eeb1
ED97: 86 41       LDA    #$41
ED99: 8E 00 20    LDX    #$0020
ED9C: BD EE B1    JSR    fill_words_eeb1
ED9F: 96 14       LDA    <$14                   ; <$14=maze colour
EDA1: 8E 01 C0    LDX    #$01C0
EDA4: BD EE B1    JSR    fill_words_eeb1
EDA7: 86 43       LDA    #$43
EDA9: 8E 00 10    LDX    #$0010
EDAC: BD EE B1    JSR    fill_words_eeb1
EDAF: 86 42       LDA    #$42
EDB1: 8E 00 10    LDX    #$0010
EDB4: BD EE B1    JSR    fill_words_eeb1
EDB7: CE 03 D4    LDU    #$03D4
EDBA: BD EE C3    JSR    print_inline_string_vert_eec3 ; [no_return] ; prints the INLINE string at $EDBD-$EDCD (bytes not in this listing, ends with $00), then continues after it

draw_item_history_edce:
EDCE: CE 00 02    LDU    #$0002
EDD1: 8E 10 08    LDX    #$1008
EDD4: C6 FF       LDB    #$FF
EDD6: 5C          INCB
EDD7: 8D 05       BSR    draw_item_icon_edde
EDD9: D1 11       CMPB   <$11                   ; <$11=item history count
EDDB: 26 F9       BNE    $EDD6
EDDD: 39          RTS

draw_item_icon_edde:
EDDE: A6 85       LDA    B,X
EDE0: 8B 0C       ADDA   #$0C
EDE2: A7 C9 04 00 STA    $0400,U
EDE6: A7 C9 04 01 STA    $0401,U
EDEA: A7 C9 04 20 STA    $0420,U
EDEE: A7 C9 04 21 STA    $0421,U
EDF2: A6 85       LDA    B,X
EDF4: 48          ASLA
EDF5: 48          ASLA
EDF6: 8B 60       ADDA   #$60

draw_2x2_tile_edf8:
EDF8: A7 C1       STA    ,U++
EDFA: 4C          INCA
EDFB: A7 C8 1E    STA    $1E,U
EDFE: 4C          INCA
EDFF: A7 5F       STA    -$1,U
EE01: 4C          INCA
EE02: A7 C8 1F    STA    $1F,U
EE05: 39          RTS

;----------------------------------------------------------------------------
; Clear the screen and draw the lives / credit status.
;----------------------------------------------------------------------------
clear_screen_and_status_ee06:
EE06: BD ED 8C    JSR    clear_screen_ed8c

draw_lives_ee09:
EE09: 96 C7       LDA    <$C7                   ; <$C7=attract flag
EE0B: 26 2B       BNE    $EE38
EE0D: CE 00 12    LDU    #$0012
EE10: C6 06       LDB    #$06
EE12: D0 07       SUBB   <$07                   ; <$07=lives left
EE14: 23 0F       BLS    $EE25
EE16: 86 20       LDA    #$20
EE18: A7 C1       STA    ,U++
EE1A: A7 C8 1E    STA    $1E,U
EE1D: A7 5F       STA    -$1,U
EE1F: A7 C8 1F    STA    $1F,U
EE22: 5A          DECB
EE23: 26 F3       BNE    $EE18
EE25: D6 07       LDB    <$07                   ; <$07=lives left
EE27: 26 01       BNE    $EE2A
EE29: 39          RTS
EE2A: C1 06       CMPB   #$06
EE2C: 25 02       BCS    $EE30
EE2E: C6 06       LDB    #$06
EE30: 86 24       LDA    #$24
EE32: 8D C4       BSR    draw_2x2_tile_edf8
EE34: 5A          DECB
EE35: 26 F9       BNE    $EE30
EE37: 39          RTS
EE38: 86 42       LDA    #$42
EE3A: CE 04 32    LDU    #$0432
EE3D: 8E 00 06    LDX    #$0006
EE40: BD EE B1    JSR    fill_words_eeb1
EE43: CE 00 3C    LDU    #$003C
EE46: 96 C0       LDA    <$C0                   ; <$C0=credits
EE48: 4C          INCA
EE49: 26 0E       BNE    print_credit_ee59
EE4B: BD EE C3    JSR    print_inline_string_vert_eec3 ; [no_return] ; prints the INLINE string at $EE4E-$EE53 (bytes not in this listing, ends with $00), then continues after it


EE58: 39          RTS                           ; real instruction (was mis-disassembled)

print_credit_ee59:
EE59: BD EE C3    JSR    print_inline_string_vert_eec3 ; [no_return] ; prints the INLINE string at $EE5C-$EE5E (bytes not in this listing, ends with $00), then continues after it


EE64: 39          RTS                           ; real instruction (was mis-disassembled)

;----------------------------------------------------------------------------
; Draw the maze from the compressed data at $EED7 (run lengths, mirrored left/right).
;----------------------------------------------------------------------------
draw_maze_ee65:
EE65: 8D 9F       BSR    clear_screen_and_status_ee06
EE67: 8E EE D7    LDX    #$EED7
EE6A: CE 00 40    LDU    #$0040
EE6D: A6 80       LDA    ,X+
EE6F: 26 01       BNE    $EE72
EE71: 39          RTS
EE72: 8D 02       BSR    maze_decode_byte_ee76
EE74: 20 F7       BRA    $EE6D

maze_decode_byte_ee76:
EE76: 2B 14       BMI    $EE8C
EE78: 85 40       BITA   #$40
EE7A: 26 0A       BNE    $EE86
EE7C: 1F 89       TFR    A,B
EE7E: 86 20       LDA    #$20
EE80: 8D 06       BSR    maze_put_tile_ee88
EE82: 5A          DECB
EE83: 26 FB       BNE    $EE80
EE85: 39          RTS
EE86: 8A C0       ORA    #$C0

maze_put_tile_ee88:
EE88: A7 C4       STA    ,U
EE8A: 20 0A       BRA    $EE96
EE8C: 85 40       BITA   #$40
EE8E: 26 17       BNE    $EEA7
EE90: 8A C0       ORA    #$C0

maze_put_mirrored_ee92:
EE92: A7 C4       STA    ,U
EE94: 88 01       EORA   #$01
EE96: 34 40       PSHS   U
EE98: 1E 30       EXG    U,D
EE9A: C8 E0       EORB   #$E0
EE9C: 88 03       EORA   #$03
EE9E: 1E 03       EXG    D,U
EEA0: A7 C4       STA    ,U
EEA2: 35 40       PULS   U
EEA4: 33 41       LEAU   $1,U
EEA6: 39          RTS
EEA7: E6 80       LDB    ,X+
EEA9: 8D E7       BSR    maze_put_mirrored_ee92
EEAB: 88 01       EORA   #$01
EEAD: 5A          DECB
EEAE: 26 F9       BNE    $EEA9
EEB0: 39          RTS

;----------------------------------------------------------------------------
; Fill X words at U with D (A=B).
;----------------------------------------------------------------------------
fill_words_eeb1:
EEB1: 1F 89       TFR    A,B
EEB3: ED C1       STD    ,U++
EEB5: 30 1F       LEAX   -$1,X
EEB7: 26 FA       BNE    $EEB3
EEB9: 39          RTS

; < X: source address
; < U: destination address
; < Y: size in words

;----------------------------------------------------------------------------
; Copy Y words from (X) to (U).
;----------------------------------------------------------------------------
memcpy_eeba:
EEBA: EC 81       LDD    ,X++
EEBC: ED C1       STD    ,U++
EEBE: 31 3F       LEAY   -$1,Y
EEC0: 26 F8       BNE    memcpy_eeba
EEC2: 39          RTS

;----------------------------------------------------------------------------
; PRINT INLINE STRING (vertical: next char at U-1). Same as below.
;----------------------------------------------------------------------------
print_inline_string_vert_eec3:
EEC3: C6 FF       LDB    #$FF
EEC5: 20 02       BRA    $EEC9

;----------------------------------------------------------------------------
; PRINT INLINE STRING (was 'task_switch_eec7'). NOT a task switch: the
; string (ASCII tile codes) FOLLOWS THE JSR in the ROM and ends with $00;
; the routine prints it at U (next char at U-$20 = one column to the right
; on screen) and JUMPS BACK right after the $00. The listing does not
; contain these string bytes (gaps after each call): the converter must
; copy them from the ROM. The [no_return] tag only means 'code does not
; continue right after the JSR'.
;----------------------------------------------------------------------------
print_inline_string_eec7:
EEC7: C6 E0       LDB    #$E0
EEC9: 35 10       PULS   X                      ; use return address to load data from
EECB: A6 80       LDA    ,X+                    ; get A from X++
EECD: 27 06       BEQ    $EED5                  ; found a zero, use 2 next bytes as jump address
EECF: A7 C4       STA    ,U                     ; else save value in U
EED1: 33 C5       LEAU   B,U                    ; U += $E0
EED3: 20 F6       BRA    $EECB                  ; while A != 0
EED5: 6E 84       JMP    ,X                     ; [direct_jump]

;----------------------------------------------------------------------------
; DOORS (37). Presence bitmap at $1020 (5 bytes). EFAA draws the present
; doors, EFB5 removes all, EFC0 sets and draws all. Screen positions from
; the table $F027 (2 bytes per door, bits 0-1 hi address, b2-3 tile...).
;----------------------------------------------------------------------------
doors_init_efaa:
EFAA: 86 24       LDA    #$24
EFAC: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
EFAE: 8D 1B       BSR    door_draw_if_present_efcb
EFB0: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
EFB2: 2A FA       BPL    $EFAE
EFB4: 39          RTS

doors_clear_efb5:
EFB5: 86 24       LDA    #$24
EFB7: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
EFB9: 8D 18       BSR    door_remove_efd3
EFBB: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
EFBD: 2A FA       BPL    $EFB9
EFBF: 39          RTS

doors_set_all_efc0:
EFC0: 86 24       LDA    #$24
EFC2: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
EFC4: 8D 1D       BSR    door_add_efe3
EFC6: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
EFC8: 2A FA       BPL    $EFC4
EFCA: 39          RTS

door_draw_if_present_efcb:
EFCB: 8D 23       BSR    item_bit_address_eff0
EFCD: E5 84       BITB   ,X
EFCF: 27 09       BEQ    $EFDA
EFD1: 20 16       BRA    $EFE9

door_remove_efd3:
EFD3: 8D 1B       BSR    item_bit_address_eff0
EFD5: 53          COMB
EFD6: E4 84       ANDB   ,X
EFD8: E7 84       STB    ,X
EFDA: 8D 2B       BSR    door_screen_address_f007
EFDC: 86 20       LDA    #$20
EFDE: A7 C4       STA    ,U
EFE0: A7 C5       STA    B,U
EFE2: 39          RTS

door_add_efe3:
EFE3: 8D 0B       BSR    item_bit_address_eff0
EFE5: EA 84       ORB    ,X
EFE7: E7 84       STB    ,X
EFE9: 8D 1C       BSR    door_screen_address_f007
EFEB: A7 C4       STA    ,U
EFED: A7 C5       STA    B,U
EFEF: 39          RTS

item_bit_address_eff0:
EFF0: 8E 10 20    LDX    #$1020
EFF3: D6 F8       LDB    <$F8                   ; <$F8=temp / loop counter
EFF5: 54          LSRB
EFF6: 54          LSRB
EFF7: 54          LSRB
EFF8: 3A          ABX
EFF9: C6 01       LDB    #$01
EFFB: 96 F8       LDA    <$F8                   ; <$F8=temp / loop counter
EFFD: 84 07       ANDA   #$07
EFFF: 26 01       BNE    $F002
F001: 39          RTS
F002: 58          ASLB
F003: 4A          DECA
F004: 26 FC       BNE    $F002
F006: 39          RTS

door_screen_address_f007:
F007: 8E F0 27    LDX    #$F027

table_screen_address_f00a:
F00A: D6 F8       LDB    <$F8                   ; <$F8=temp / loop counter
F00C: 58          ASLB
F00D: 3A          ABX
F00E: EC 84       LDD    ,X
F010: 84 03       ANDA   #$03
F012: CE 00 00    LDU    #$0000
F015: 33 CB       LEAU   D,U
F017: A6 84       LDA    ,X
F019: 44          LSRA
F01A: 44          LSRA
F01B: 8B E0       ADDA   #$E0
F01D: C6 20       LDB    #$20
F01F: 85 10       BITA   #$10
F021: 26 01       BNE    $F024
F023: 39          RTS
F024: C6 01       LDB    #$01
F026: 39          RTS

;----------------------------------------------------------------------------
; SLOT 2 TASK: OBJECT MANAGER (set by enable_object_tasks_e29e). First call: every object gets runner
; runner_kill_object_f0e5 and its sprite entry ($0F00+2n), maze wall data
; copied to $1160. Then every frame: for each object record ($0810-$0F0F,
; 56 records, and $1610-$170F, 8 records, $20 bytes each) JSR [4,U] = its
; runner.
; OBJECT RECORD (U points 16 bytes into a 32-byte block):
;  ,U resume PC   2,U wait counter   4,U runner   6,U sprite entry ptr
;  9,U size/flip  A,U sprite code    B,U colour   C,U y   D,U x
;  E/F,U speed accumulator   -$10,U speed   -$D,U direction (0 up..3)
;  -$E,U wanted direction  -$C,U maze exits  -$B/-$A,U type / index.
;----------------------------------------------------------------------------
object_manager_task_f085:
F085: CC F0 E5    LDD    #$F0E5
F088: 8E 0F 00    LDX    #$0F00
F08B: CE 08 10    LDU    #$0810
F08E: ED 44       STD    $4,U
F090: AF 46       STX    $6,U
F092: 33 C8 20    LEAU   $20,U
F095: 30 02       LEAX   $2,X
F097: 8C 0F 70    CMPX   #$0F70
F09A: 26 F2       BNE    $F08E
F09C: CE 16 10    LDU    #$1610
F09F: ED 44       STD    $4,U
F0A1: AF 46       STX    $6,U
F0A3: 33 C8 20    LEAU   $20,U
F0A6: 30 02       LEAX   $2,X
F0A8: 8C 0F 80    CMPX   #$0F80
F0AB: 26 F2       BNE    $F09F
F0AD: 8D 10       BSR    run_all_objects_f0bf
F0AF: 8E F1 45    LDX    #$F145
F0B2: CE 11 60    LDU    #$1160
F0B5: 10 8E 00 10 LDY    #$0010
F0B9: BD EE BA    JSR    memcpy_eeba
F0BC: BD E2 B4    JSR    task_yield_e2b4

run_all_objects_f0bf:
F0BF: CE 08 10    LDU    #$0810                 ; first object record
F0C2: AD D8 04    JSR    [$04,U]                ; [indirect_jump] ; call the object runner
F0C5: 33 C8 20    LEAU   $20,U                  ; advance to next record
F0C8: 11 83 0F 10 CMPU   #$0F10                 ; end of object table?
F0CC: 26 F4       BNE    $F0C2
F0CE: CE 16 10    LDU    #$1610
F0D1: AD D8 04    JSR    [$04,U]                ; [indirect_jump]
F0D4: 33 C8 20    LEAU   $20,U
F0D7: 11 83 17 10 CMPU   #$1710
F0DB: 26 F4       BNE    $F0D1
F0DD: 39          RTS

;----------------------------------------------------------------------------
; RUNNER: resume the task coroutine of record U (PSHS U / JSR [,U] / PULS U).
;----------------------------------------------------------------------------
runner_resume_f0de:
F0DE: 34 40       PSHS   U
F0E0: AD D4       JSR    [,U]                   ; [indirect_jump] ; resume the object coroutine
F0E2: 35 40       PULS   U
F0E4: 39          RTS

;----------------------------------------------------------------------------
; RUNNER: kill object: state = RTS, sprite y = 0 (hidden), runner = F0DE.
;----------------------------------------------------------------------------
runner_kill_object_f0e5:
F0E5: CC E2 BA    LDD    #$e2ba                 ; [function_address] ; -> task_nop_rts_e2ba
F0E8: ED C4       STD    ,U
F0EA: CC 00 00    LDD    #$0000
F0ED: ED 42       STD    $2,U

runner_hide_sprite_f0ef:
F0EF: CC 00 00    LDD    #$0000
F0F2: ED 4C       STD    $C,U
F0F4: CC F0 DE    LDD    #$f0de                 ; [function_address] ; -> runner_resume_f0de
F0F7: ED 44       STD    $4,U
F0F9: 20 06       BRA    runner_draw_sprite_f101

;----------------------------------------------------------------------------
; RUNNER: resume the coroutine then copy the object into its sprite entry (F101).
;----------------------------------------------------------------------------
runner_resume_and_draw_f0fb:
F0FB: 34 40       PSHS   U
F0FD: AD D4       JSR    [,U]                   ; [indirect_jump] ; resume the object coroutine
F0FF: 35 40       PULS   U

;----------------------------------------------------------------------------
; Object -> sprite buffers: code/colour at (6,U) ($0F00..), y/x at +$800
; ($1700..), flags/x msb at +$1000 ($1F00..). Adjusts for flip and size.
;----------------------------------------------------------------------------
runner_draw_sprite_f101:
F101: AE 46       LDX    $6,U
F103: EC 4A       LDD    $A,U
F105: ED 84       STD    ,X
F107: E6 4D       LDB    $D,U
F109: 96 85       LDA    <$85                   ; <$85=screen flipped (cocktail P2)
F10B: 27 06       BEQ    $F113
F10D: 86 FF       LDA    #$FF
F10F: 53          COMB
F110: C3 01 01    ADDD   #$0101
F113: C3 00 28    ADDD   #$0028
F116: 34 02       PSHS   A
F118: A6 49       LDA    $9,U
F11A: 85 04       BITA   #$04
F11C: 35 02       PULS   A
F11E: 26 03       BNE    $F123
F120: C3 00 08    ADDD   #$0008
F123: E7 89 08 01 STB    $0801,X
F127: A7 89 10 01 STA    $1001,X
F12B: E6 4C       LDB    $C,U
F12D: 96 85       LDA    <$85                   ; <$85=screen flipped (cocktail P2)
F12F: 26 01       BNE    $F132
F131: 50          NEGB
F132: CB F1       ADDB   #$F1
F134: A6 49       LDA    $9,U
F136: 85 08       BITA   #$08
F138: 26 02       BNE    $F13C
F13A: CB 08       ADDB   #$08
F13C: E7 89 08 00 STB    $0800,X
F140: A7 89 10 00 STA    $1000,X
F144: 39          RTS

;----------------------------------------------------------------------------
; KEYS (15 objects at $0810..). Presence bitmap $1025. F165 spawn present keys, F17A remove all, F18F add all.
;----------------------------------------------------------------------------
keys_init_f165:
F165: 86 0E       LDA    #$0E
F167: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
F169: CE 08 10    LDU    #$0810
F16C: 96 F8       LDA    <$F8                   ; <$F8=temp / loop counter
F16E: A7 56       STA    -$A,U
F170: 8D 32       BSR    key_spawn_if_present_f1a4
F172: 33 C8 20    LEAU   $20,U
F175: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
F177: 2A F3       BPL    $F16C
F179: 39          RTS

keys_clear_f17a:
F17A: 86 0E       LDA    #$0E
F17C: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
F17E: CE 08 10    LDU    #$0810
F181: 96 F8       LDA    <$F8                   ; <$F8=temp / loop counter
F183: A7 56       STA    -$A,U
F185: 8D 25       BSR    key_remove_f1ac
F187: 33 C8 20    LEAU   $20,U
F18A: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
F18C: 2A F3       BPL    $F181
F18E: 39          RTS

keys_set_all_f18f:
F18F: 86 0E       LDA    #$0E
F191: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
F193: CE 08 10    LDU    #$0810
F196: 96 F8       LDA    <$F8                   ; <$F8=temp / loop counter
F198: A7 56       STA    -$A,U
F19A: 8D 1D       BSR    key_spawn_f1b9
F19C: 33 C8 20    LEAU   $20,U
F19F: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
F1A1: 2A F3       BPL    $F196
F1A3: 39          RTS

key_spawn_if_present_f1a4:
F1A4: 8D 37       BSR    key_bit_address_f1dd
F1A6: E5 84       BITB   ,X
F1A8: 27 09       BEQ    $F1B3
F1AA: 20 13       BRA    $F1BF

key_remove_f1ac:
F1AC: 8D 2F       BSR    key_bit_address_f1dd
F1AE: 53          COMB
F1AF: E4 84       ANDB   ,X
F1B1: E7 84       STB    ,X
F1B3: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
F1B6: ED 44       STD    $4,U
F1B8: 39          RTS

key_spawn_f1b9:
F1B9: 8D 22       BSR    key_bit_address_f1dd
F1BB: EA 84       ORB    ,X
F1BD: E7 84       STB    ,X
F1BF: E6 56       LDB    -$A,U
F1C1: 58          ASLB
F1C2: 8E F2 33    LDX    #$F233
F1C5: EC 85       LDD    B,X
F1C7: ED 4C       STD    $C,U
F1C9: CC 00 40    LDD    #$0040
F1CC: ED 49       STD    $9,U
F1CE: 86 24       LDA    #$24
F1D0: A7 4B       STA    $B,U
F1D2: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
F1D5: ED 44       STD    $4,U
F1D7: CC F1 F4    LDD    #$f1f4                 ; [function_address] ; -> key_task_f1f4
F1DA: ED C4       STD    ,U
F1DC: 39          RTS

key_bit_address_f1dd:
F1DD: 8E 10 25    LDX    #$1025

item_bit_address_f1e0:
F1E0: E6 56       LDB    -$A,U
F1E2: 54          LSRB
F1E3: 54          LSRB
F1E4: 54          LSRB
F1E5: 3A          ABX
F1E6: C6 01       LDB    #$01
F1E8: A6 56       LDA    -$A,U
F1EA: 84 07       ANDA   #$07
F1EC: 26 01       BNE    $F1EF
F1EE: 39          RTS
F1EF: 58          ASLB
F1F0: 4A          DECA
F1F1: 26 FC       BNE    $F1EF
F1F3: 39          RTS

;----------------------------------------------------------------------------
; Key object task: when Pac-Man touches it: sound $4049, key removed, opens its doors (table $F251), score.
;----------------------------------------------------------------------------
key_task_f1f4:
F1F4: BD E2 B4    JSR    task_yield_e2b4
F1F7: CC F0 DE    LDD    #$f0de                 ; [function_address] ; -> runner_resume_f0de
F1FA: ED 44       STD    $4,U
F1FC: BD E2 B4    JSR    task_yield_e2b4
F1FF: BD F6 AC    JSR    collision_with_pacman_f6ac
F202: 25 01       BCS    $F205
F204: 39          RTS
F205: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F207: B7 40 49    STA    $4049                  ; SOUND: key eaten
F20A: 8D A0       BSR    key_remove_f1ac
F20C: A6 56       LDA    -$A,U
F20E: 48          ASLA
F20F: 48          ASLA
F210: 9B 16       ADDA   <$16
F212: C6 03       LDB    #$03
F214: D7 F9       STB    <$F9
F216: 3D          MUL
F217: 8E F2 51    LDX    #$F251
F21A: 30 8B       LEAX   D,X
F21C: A6 80       LDA    ,X+
F21E: 2B 09       BMI    $F229
F220: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
F222: 34 10       PSHS   X
F224: BD EF D3    JSR    door_remove_efd3
F227: 35 10       PULS   X
F229: 0A F9       DEC    <$F9
F22B: 26 EF       BNE    $F21C
F22D: CC 00 05    LDD    #$0005
F230: 7E FD 6B    JMP    add_score_fd6b

;----------------------------------------------------------------------------
; FRUITS / food (31 objects at $09F0..). Bitmap $1027, count <$90.
;----------------------------------------------------------------------------
fruits_init_f305:
F305: 86 1E       LDA    #$1E
F307: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
F309: 0F 90       CLR    <$90                   ; <$90=fruits left
F30B: CE 09 F0    LDU    #$09F0
F30E: 96 F8       LDA    <$F8                   ; <$F8=temp / loop counter
F310: A7 56       STA    -$A,U
F312: 8D 36       BSR    fruit_spawn_if_present_f34a
F314: 33 C8 20    LEAU   $20,U
F317: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
F319: 2A F3       BPL    $F30E
F31B: 39          RTS

fruits_clear_f31c:
F31C: 86 1E       LDA    #$1E
F31E: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
F320: CE 09 F0    LDU    #$09F0
F323: 96 F8       LDA    <$F8                   ; <$F8=temp / loop counter
F325: A7 56       STA    -$A,U
F327: 8D 29       BSR    fruit_remove_f352
F329: 33 C8 20    LEAU   $20,U
F32C: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
F32E: 2A F3       BPL    $F323
F330: 0F 90       CLR    <$90                   ; <$90=fruits left
F332: 39          RTS

fruits_set_all_f333:
F333: 86 1E       LDA    #$1E
F335: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
F337: 0F 90       CLR    <$90                   ; <$90=fruits left
F339: CE 09 F0    LDU    #$09F0
F33C: 96 F8       LDA    <$F8                   ; <$F8=temp / loop counter
F33E: A7 56       STA    -$A,U
F340: 8D 1F       BSR    fruit_spawn_f361
F342: 33 C8 20    LEAU   $20,U
F345: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
F347: 2A F3       BPL    $F33C
F349: 39          RTS

fruit_spawn_if_present_f34a:
F34A: 8D 3F       BSR    fruit_bit_address_f38b
F34C: E5 84       BITB   ,X
F34E: 27 0B       BEQ    $F35B
F350: 20 15       BRA    $F367

fruit_remove_f352:
F352: 8D 37       BSR    fruit_bit_address_f38b
F354: 53          COMB
F355: E4 84       ANDB   ,X
F357: E7 84       STB    ,X
F359: 0A 90       DEC    <$90                   ; <$90=fruits left
F35B: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
F35E: ED 44       STD    $4,U
F360: 39          RTS

fruit_spawn_f361:
F361: 8D 28       BSR    fruit_bit_address_f38b
F363: EA 84       ORB    ,X
F365: E7 84       STB    ,X
F367: 0C 90       INC    <$90                   ; <$90=fruits left
F369: E6 56       LDB    -$A,U
F36B: 58          ASLB
F36C: 8E F3 B2    LDX    #$F3B2
F36F: EC 85       LDD    B,X
F371: ED 4C       STD    $C,U
F373: 4F          CLRA
F374: D6 10       LDB    <$10                   ; <$10=bonus item type of the level
F376: CB 44       ADDB   #$44
F378: ED 49       STD    $9,U
F37A: 96 10       LDA    <$10                   ; <$10=bonus item type of the level
F37C: 8B 10       ADDA   #$10
F37E: A7 4B       STA    $B,U
F380: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
F383: ED 44       STD    $4,U
F385: CC F3 91    LDD    #$F391                 ; [function_address] ; -> fruit_task_f391
F388: ED C4       STD    ,U
F38A: 39          RTS

fruit_bit_address_f38b:
F38B: 8E 10 27    LDX    #$1027
F38E: 7E F1 E0    JMP    item_bit_address_f1e0

;----------------------------------------------------------------------------
; Fruit object task: eaten by Pac-Man -> sound $404A, score, bonus item check.
;----------------------------------------------------------------------------
fruit_task_f391:
F391: BD E2 B4    JSR    task_yield_e2b4
F394: CC F0 DE    LDD    #$f0de                 ; [function_address] ; -> runner_resume_f0de
F397: ED 44       STD    $4,U
F399: BD E2 B4    JSR    task_yield_e2b4
F39C: BD F6 AC    JSR    collision_with_pacman_f6ac
F39F: 25 01       BCS    $F3A2
F3A1: 39          RTS
F3A2: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F3A4: B7 40 4A    STA    $404A                  ; SOUND: fruit eaten
F3A7: 8D A9       BSR    fruit_remove_f352
F3A9: D6 13       LDB    <$13                   ; <$13=round number (BCD)
F3AB: 4F          CLRA
F3AC: BD FD 6B    JSR    add_score_fd6b
F3AF: 7E FB C2    JMP    check_bonus_items_fbc2

;----------------------------------------------------------------------------
; POWER PELLETS (6 objects at $0DD0..): indexes 0-1 = SUPER pellets, 2-5 = power pellets. Bitmap $102B, count <$91.
;----------------------------------------------------------------------------
pellets_init_f3f0:
F3F0: 86 05       LDA    #$05
F3F2: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
F3F4: 0F 91       CLR    <$91                   ; <$91=power pellets left
F3F6: CE 0D D0    LDU    #$0DD0
F3F9: 96 F8       LDA    <$F8                   ; <$F8=temp / loop counter
F3FB: A7 56       STA    -$A,U
F3FD: 8D 36       BSR    pellet_spawn_if_present_f435
F3FF: 33 C8 20    LEAU   $20,U
F402: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
F404: 2A F3       BPL    $F3F9
F406: 39          RTS

pellets_clear_f407:
F407: 86 05       LDA    #$05
F409: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
F40B: CE 0D D0    LDU    #$0DD0
F40E: 96 F8       LDA    <$F8                   ; <$F8=temp / loop counter
F410: A7 56       STA    -$A,U
F412: 8D 29       BSR    pellet_remove_f43d
F414: 33 C8 20    LEAU   $20,U
F417: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
F419: 2A F3       BPL    $F40E
F41B: 0F 91       CLR    <$91                   ; <$91=power pellets left
F41D: 39          RTS

pellets_set_all_f41e:
F41E: 86 05       LDA    #$05
F420: 97 F8       STA    <$F8                   ; <$F8=temp / loop counter
F422: 0F 91       CLR    <$91                   ; <$91=power pellets left
F424: CE 0D D0    LDU    #$0DD0
F427: 96 F8       LDA    <$F8                   ; <$F8=temp / loop counter
F429: A7 56       STA    -$A,U
F42B: 8D 1F       BSR    pellet_spawn_f44c
F42D: 33 C8 20    LEAU   $20,U
F430: 0A F8       DEC    <$F8                   ; <$F8=temp / loop counter
F432: 2A F3       BPL    $F427
F434: 39          RTS

pellet_spawn_if_present_f435:
F435: 8D 47       BSR    pellet_bit_address_f47e
F437: E5 84       BITB   ,X
F439: 27 0B       BEQ    $F446
F43B: 20 15       BRA    $F452

pellet_remove_f43d:
F43D: 8D 3F       BSR    pellet_bit_address_f47e
F43F: 53          COMB
F440: E4 84       ANDB   ,X
F442: E7 84       STB    ,X
F444: 0A 91       DEC    <$91                   ; <$91=power pellets left
F446: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
F449: ED 44       STD    $4,U
F44B: 39          RTS

pellet_spawn_f44c:
F44C: 8D 30       BSR    pellet_bit_address_f47e
F44E: EA 84       ORB    ,X
F450: E7 84       STB    ,X
F452: 0C 91       INC    <$91                   ; <$91=power pellets left
F454: A6 56       LDA    -$A,U
F456: 48          ASLA
F457: 8E F4 84    LDX    #$F484
F45A: AE 86       LDX    A,X
F45C: 4F          CLRA
F45D: E6 56       LDB    -$A,U
F45F: C0 02       SUBB   #$02
F461: 24 01       BCC    $F464
F463: 4C          INCA
F464: 8D 06       BSR    pellet_setup_f46c
F466: CC F4 90    LDD    #$F490
F469: ED C4       STD    ,U
F46B: 39          RTS

;----------------------------------------------------------------------------
; Pellet object setup: -$B,U = 1 super / 0 power, sprite code $41+type, position X.
;----------------------------------------------------------------------------
pellet_setup_f46c:
F46C: A7 55       STA    -$B,U
F46E: 8B 41       ADDA   #$41
F470: A7 4A       STA    $A,U
F472: AF 4C       STX    $C,U
F474: 6F 49       CLR    $9,U
F476: 6F 42       CLR    $2,U
F478: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
F47B: ED 44       STD    $4,U
F47D: 39          RTS

pellet_bit_address_f47e:
F47E: 8E 10 2B    LDX    #$102B
F481: 7E F1 E0    JMP    item_bit_address_f1e0


;----------------------------------------------------------------------------
; Pellet object task. 
;----------------------------------------------------------------------------
pellet_task_f490:
F490: A6 55       LDA    -$B,U                  ; pellet type: 0 power / 1 super (was mis-disassembled)
F492: 27 47       BEQ    power_pellet_state_f4db
F494: 8D 2A       BSR    super_pellet_colour_cycle_f4c0
F496: BD F6 AC    JSR    collision_with_pacman_f6ac
F499: 25 01       BCS    $F49C
F49B: 39          RTS

F49C: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F49E: B7 40 51    STA    $4051                  ; SOUND: super pellet eaten
F4A1: BD F4 3D    JSR    pellet_remove_f43d
F4A4: CC 00 10    LDD    #$0010
F4A7: BD FD 6B    JSR    add_score_fd6b
F4AA: BD FB C2    JSR    check_bonus_items_fbc2
F4AD: 96 96       LDA    <$96                   ; <$96=bonus stage flag
F4AF: 27 01       BEQ    $F4B2
F4B1: 39          RTS
F4B2: CE 16 30    LDU    #$1630
F4B5: CC 01 01    LDD    #$0101
F4B8: ED 55       STD    -$B,U
F4BA: CC F5 BD    LDD    #$F5BD                 ; [function_address] ; -> super_pacman_task_f5bd
F4BD: ED C4       STD    ,U
F4BF: 39          RTS

super_pellet_colour_cycle_f4c0:
F4C0: A6 42       LDA    $2,U
F4C2: 4C          INCA
F4C3: 81 30       CMPA   #$30
F4C5: 26 01       BNE    $F4C8
F4C7: 4F          CLRA
F4C8: A7 42       STA    $2,U
F4CA: 44          LSRA
F4CB: 44          LSRA
F4CC: 44          LSRA
F4CD: 8E F4 D5    LDX    #$F4D5
F4D0: A6 86       LDA    A,X
F4D2: A7 4B       STA    $B,U
F4D4: 39          RTS

power_pellet_state_f4db:
F4DB: 8D 1F       BSR    power_pellet_blink_f4fc
F4DD: BD F6 AC    JSR    collision_with_pacman_f6ac
F4E0: 25 01       BCS    $F4E3
F4E2: 39          RTS
F4E3: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F4E5: B7 40 4A    STA    $404A                  ; SOUND: fruit eaten
F4E8: BD F4 3D    JSR    pellet_remove_f43d
F4EB: CC 00 10    LDD    #$0010
F4EE: BD FD 6B    JSR    add_score_fd6b
F4F1: BD FB C2    JSR    check_bonus_items_fbc2
F4F4: 96 96       LDA    <$96                   ; <$96=bonus stage flag
F4F6: 27 01       BEQ    $F4F9
F4F8: 39          RTS
F4F9: 7E FD 43    JMP    power_pellet_eaten_fd43

power_pellet_blink_f4fc:
F4FC: 4F          CLRA
F4FD: D6 81       LDB    <$81                   ; <$81=frame counter
F4FF: C5 08       BITB   #$08
F501: 26 02       BNE    $F505
F503: 86 0B       LDA    #$0B
F505: A7 4B       STA    $B,U
F507: 39          RTS

;----------------------------------------------------------------------------
; Create the Pac-Man object ($1630) at its start position; bonus stage version if <$96.
;----------------------------------------------------------------------------
pacman_start_f508:
F508: 8E 80 78    LDX    #$8078
F50B: CC 01 03    LDD    #$0103
F50E: 8D 0E       BSR    pacman_object_setup_f51e
F510: 8E F5 DB    LDX    #$F5DB                 ; [function_address] ; -> pacman_task_f5db
F513: 96 96       LDA    <$96                   ; <$96=bonus stage flag
F515: 27 03       BEQ    $F51A
F517: 8E F5 A3    LDX    #$F5A3                 ; [function_address] ; -> pacman_bonus_stage_task_f5a3
F51A: AF C4       STX    ,U
F51C: 6E 84       JMP    ,X

;----------------------------------------------------------------------------
; Pac-Man object setup (U=$1630): position X, colour A, direction B.
;----------------------------------------------------------------------------
pacman_object_setup_f51e:
F51E: CE 16 30    LDU    #$1630
F521: AF 4C       STX    $C,U
F523: A7 4B       STA    $B,U
F525: E7 52       STB    -$E,U
F527: E7 53       STB    -$D,U
F529: CC 00 00    LDD    #$0000
F52C: ED 4E       STD    $E,U
F52E: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
F531: ED 44       STD    $4,U
F533: 39          RTS

pacman_remove_f534:
F534: CE 16 30    LDU    #$1630
F537: 4F          CLRA
F538: A7 56       STA    -$A,U
F53A: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
F53D: ED 44       STD    $4,U
F53F: 39          RTS

;----------------------------------------------------------------------------
; Move Pac-Man by its speed, turning at the maze intersections.
;----------------------------------------------------------------------------
pacman_move_f540:
F540: AE 4E       LDX    $E,U
F542: EC 50       LDD    -$10,U
F544: 30 8B       LEAX   D,X
F546: AF 4E       STX    $E,U
F548: A6 4E       LDA    $E,U
F54A: 26 01       BNE    $F54D
F54C: 39          RTS
F54D: 8D 08       BSR    pacman_turn_check_f557
F54F: BD FA 48    JSR    object_step_one_pixel_fa48
F552: 6A 4E       DEC    $E,U
F554: 26 F7       BNE    $F54D
F556: 39          RTS

pacman_turn_check_f557:
F557: A6 52       LDA    -$E,U
F559: 88 02       EORA   #$02
F55B: A1 53       CMPA   -$D,U
F55D: 27 29       BEQ    $F588
F55F: E6 4C       LDB    $C,U
F561: C0 1C       SUBB   #$1C
F563: BD FB AA    JSR    div_by_20_fbaa
F566: 27 01       BEQ    $F569
F568: 39          RTS
F569: D7 FE       STB    <$FE
F56B: E6 4D       LDB    $D,U
F56D: C0 14       SUBB   #$14
F56F: BD FB AA    JSR    div_by_20_fbaa
F572: 27 01       BEQ    $F575
F574: 39          RTS
F575: D7 FF       STB    <$FF
F577: BD FA AC    JSR    maze_get_exits_faac
F57A: BD FA FB    JSR    maze_block_up_in_tunnel_fafb
F57D: A6 52       LDA    -$E,U
F57F: A1 53       CMPA   -$D,U
F581: 27 13       BEQ    $F596
F583: BD FA A5    JSR    test_exit_bit_faa5
F586: 25 09       BCS    $F591
F588: A6 52       LDA    -$E,U
F58A: A7 53       STA    -$D,U
F58C: 86 04       LDA    #$04
F58E: A7 4E       STA    $E,U
F590: 39          RTS
F591: A6 53       LDA    -$D,U
F593: 2A 01       BPL    $F596
F595: 39          RTS
F596: BD FA A5    JSR    test_exit_bit_faa5
F599: 25 01       BCS    $F59C
F59B: 39          RTS
F59C: A6 53       LDA    -$D,U
F59E: 8A 80       ORA    #$80
F5A0: A7 53       STA    -$D,U
F5A2: 39          RTS

pacman_bonus_stage_task_f5a3:
F5A3: CC 01 01    LDD    #$0101
F5A6: ED 55       STD    -$B,U
F5A8: C6 01       LDB    #$01

pacman_set_size_f5aa:
F5AA: 4F          CLRA
F5AB: B7 11 70    STA    $1170
F5AE: B7 11 78    STA    $1178
F5B1: 8D 2F       BSR    pacman_frame_f5e2
F5B3: CC 5A 3C    LDD    #$5A3C
F5B6: B7 11 70    STA    $1170
F5B9: F7 11 78    STB    $1178
F5BC: 39          RTS

;----------------------------------------------------------------------------
; SUPER Pac-Man state: big sprite during <$9A frames (blinks at the end), then back to normal.
;----------------------------------------------------------------------------
super_pacman_task_f5bd:
F5BD: DC 9A       LDD    <$9A                   ; <$9A=super Pac-Man duration
F5BF: 27 1A       BEQ    pacman_task_f5db
F5C1: BD E2 BB    JSR    task_wait_init_e2bb
F5C4: EC 42       LDD    $2,U
F5C6: 10 83 00 40 CMPD   #$0040
F5CA: 24 08       BCC    $F5D4
F5CC: C4 08       ANDB   #$08
F5CE: 54          LSRB
F5CF: 54          LSRB
F5D0: 54          LSRB
F5D1: 5C          INCB
F5D2: 20 02       BRA    $F5D6
F5D4: C6 01       LDB    #$01
F5D6: 8D D2       BSR    pacman_set_size_f5aa
F5D8: BD E2 C4    JSR    task_wait_e2c4

;----------------------------------------------------------------------------
; Normal Pac-Man task: controls, speed, movement, doors, animation.
;----------------------------------------------------------------------------
pacman_task_f5db:
F5DB: CC 00 00    LDD    #$0000
F5DE: ED 55       STD    -$B,U
F5E0: C6 01       LDB    #$01

pacman_frame_f5e2:
F5E2: E7 4B       STB    $B,U
F5E4: 8D 49       BSR    joystick_to_direction_f62f
F5E6: 8D 57       BSR    pacman_get_speed_f63f
F5E8: 7F 11 71    CLR    $1171
F5EB: BD F5 40    JSR    pacman_move_f540
F5EE: 86 5A       LDA    #$5A
F5F0: B7 11 71    STA    $1171
F5F3: 34 40       PSHS   U
F5F5: BD F6 C5    JSR    pacman_open_doors_f6c5
F5F8: 35 40       PULS   U

pacman_anim_frame_f5fa:
F5FA: A6 53       LDA    -$D,U
F5FC: 84 03       ANDA   #$03
F5FE: 27 02       BEQ    $F602
F600: 88 03       EORA   #$03
F602: E6 56       LDB    -$A,U
F604: 27 02       BEQ    $F608
F606: 8B 0C       ADDA   #$0C
F608: A7 49       STA    $9,U
F60A: 96 81       LDA    <$81                   ; <$81=frame counter
F60C: 84 07       ANDA   #$07
F60E: 8E F6 27    LDX    #$F627
F611: A6 86       LDA    A,X
F613: 27 07       BEQ    $F61C
F615: E6 53       LDB    -$D,U
F617: 54          LSRB
F618: 25 02       BCS    $F61C
F61A: 8B 02       ADDA   #$02
F61C: E6 56       LDB    -$A,U
F61E: 27 04       BEQ    $F624
F620: 48          ASLA
F621: 48          ASLA
F622: 8B 10       ADDA   #$10
F624: A7 4A       STA    $A,U
F626: 39          RTS

;----------------------------------------------------------------------------
; Controls (<$AC) -> wanted direction -$E,U.
;----------------------------------------------------------------------------
joystick_to_direction_f62f:
F62F: 96 AC       LDA    <$AC                   ; <$AC=current controls (active high)
F631: C6 00       LDB    #$00
F633: 44          LSRA
F634: 25 06       BCS    $F63C
F636: 5C          INCB
F637: C1 04       CMPB   #$04
F639: 26 F8       BNE    $F633
F63B: 39          RTS
F63C: E7 52       STB    -$E,U
F63E: 39          RTS

pacman_get_speed_f63f:
F63F: 9E 9E       LDX    <$9E                   ; <$9E=Pac-Man speed
F641: A6 56       LDA    -$A,U
F643: 27 0C       BEQ    $F651
F645: 96 AC       LDA    <$AC                   ; <$AC=current controls (active high)
F647: 8E 01 C0    LDX    #$01C0
F64A: 85 20       BITA   #$20
F64C: 27 03       BEQ    $F651
F64E: 8E 03 00    LDX    #$0300
F651: AF 50       STX    -$10,U
F653: 39          RTS

;----------------------------------------------------------------------------
; Called by the ghosts: if a ghost touches Pac-Man (and not super) -> Pac-Man death.
;----------------------------------------------------------------------------
ghost_check_catch_pacman_f654:
F654: B6 16 25    LDA    $1625
F657: 27 01       BEQ    $F65A
F659: 39          RTS
F65A: 8D 50       BSR    collision_with_pacman_f6ac
F65C: 25 01       BCS    $F65F
F65E: 39          RTS
F65F: CC F6 66    LDD    #$F666                 ; [function_address] ; -> pacman_death_task_f666
F662: FD 16 30    STD    pacman_object_1630
F665: 39          RTS

;----------------------------------------------------------------------------
; Pac-Man death: ghosts off, death animation, sound $4053, slot 1 PC := pacman_died_ea60.
;----------------------------------------------------------------------------
pacman_death_task_f666:
F666: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
F669: FD 16 54    STD    $1654
F66C: FD 16 74    STD    $1674
F66F: FD 16 14    STD    $1614
F672: BD F7 8D    JSR    set_ghosts_runner_f78d
F675: CC 00 10    LDD    #$0010
F678: BD E2 BB    JSR    task_wait_init_e2bb
F67B: BD E2 C4    JSR    task_wait_e2c4
F67E: 4F          CLRA
F67F: A7 49       STA    $9,U
F681: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F683: B7 40 53    STA    $4053                  ; SOUND: Pac-Man dies
F686: CC 00 67    LDD    #$0067
F689: BD E2 BB    JSR    task_wait_init_e2bb
F68C: A6 43       LDA    $3,U
F68E: 44          LSRA
F68F: 44          LSRA
F690: 44          LSRA
F691: 40          NEGA
F692: 8B 0F       ADDA   #$0F
F694: A7 4A       STA    $A,U
F696: BD E2 C4    JSR    task_wait_e2c4
F699: CC 00 1E    LDD    #$001E
F69C: BD E2 BB    JSR    task_wait_init_e2bb
F69F: BD E2 C4    JSR    task_wait_e2c4
F6A2: CC EA 60    LDD    #$EA60                 ; [function_address] ; slot 1 task := pacman_died_ea60 ; -> pacman_died_ea60
F6A5: FD 11 08    STD    task_slot1_1108
F6A8: BD E2 B4    JSR    task_yield_e2b4
F6AB: 39          RTS

;----------------------------------------------------------------------------
; (was 'carry_returning_f6ac') CF=1 if object U touches Pac-Man
; (|dy|+|dx| < 4, Pac-Man position at $163C). F6AF: A = distance to (D).
;----------------------------------------------------------------------------
collision_with_pacman_f6ac:
F6AC: FC 16 3C    LDD    pacman_y_163c

distance_to_pacman_f6af:
F6AF: A0 4C       SUBA   $C,U
F6B1: 24 01       BCC    $F6B4
F6B3: 40          NEGA
F6B4: E0 4D       SUBB   $D,U
F6B6: 24 01       BCC    $F6B9
F6B8: 50          NEGB
F6B9: D7 F8       STB    <$F8                   ; <$F8=temp / loop counter
F6BB: 9B F8       ADDA   <$F8                   ; <$F8=temp / loop counter
F6BD: 25 03       BCS    $F6C2
F6BF: 81 04       CMPA   #$04
F6C1: 39          RTS
F6C2: 4F          CLRA
F6C3: 4A          DECA
F6C4: 39          RTS

;----------------------------------------------------------------------------
; Pac-Man over a closed door tile ($E0/$E1/$F0/$F1): opens it (tiles, bitmap, sound $404C, score).
;----------------------------------------------------------------------------
pacman_open_doors_f6c5:
F6C5: EC 4C       LDD    $C,U
F6C7: 44          LSRA
F6C8: 44          LSRA
F6C9: 44          LSRA
F6CA: 44          LSRA
F6CB: 56          RORB
F6CC: 44          LSRA
F6CD: 56          RORB
F6CE: 44          LSRA
F6CF: 56          RORB
F6D0: 8E 00 00    LDX    #$0000
F6D3: 30 8B       LEAX   D,X
F6D5: A6 84       LDA    ,X
F6D7: 81 E0       CMPA   #$E0
F6D9: 27 0D       BEQ    $F6E8
F6DB: 81 E1       CMPA   #$E1
F6DD: 27 0D       BEQ    $F6EC
F6DF: 81 F0       CMPA   #$F0
F6E1: 27 13       BEQ    $F6F6
F6E3: 81 F1       CMPA   #$F1
F6E5: 27 13       BEQ    $F6FA
F6E7: 39          RTS
F6E8: 86 E6       LDA    #$E6
F6EA: 20 02       BRA    $F6EE
F6EC: 86 E8       LDA    #$E8
F6EE: A7 84       STA    ,X
F6F0: 4C          INCA
F6F1: 30 88 E0    LEAX   -$20,X
F6F4: 20 0B       BRA    $F701
F6F6: 86 F7       LDA    #$F7
F6F8: 20 02       BRA    $F6FC
F6FA: 86 F9       LDA    #$F9
F6FC: A7 84       STA    ,X
F6FE: 4A          DECA
F6FF: 30 1F       LEAX   -$1,X
F701: A7 84       STA    ,X
F703: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F705: B7 40 4C    STA    $404C                  ; SOUND: door opens
F708: 8D 06       BSR    door_clear_bit_f710
F70A: CC 00 20    LDD    #$0020
F70D: 7E FD 6B    JMP    add_score_fd6b

door_clear_bit_f710:
F710: 30 84       LEAX   ,X                     ; this is a no-op as Z isn't tested [nop] ; no-op (Z not tested) [nop]
F712: 9F F8       STX    <$F8                   ; <$F8=temp / loop counter
F714: 8E F0 27    LDX    #$F027
F717: EC 81       LDD    ,X++
F719: 84 03       ANDA   #$03
F71B: 93 F8       SUBD   <$F8                   ; <$F8=temp / loop counter
F71D: 27 06       BEQ    $F725
F71F: 8C F0 71    CMPX   #$F071
F722: 26 F3       BNE    $F717
F724: 39          RTS
F725: 1F 10       TFR    X,D
F727: 83 F0 29    SUBD   #$F029
F72A: 54          LSRB
F72B: D7 F8       STB    <$F8                   ; <$F8=temp / loop counter
F72D: BD EF F0    JSR    item_bit_address_eff0
F730: 53          COMB
F731: E4 84       ANDB   ,X
F733: E7 84       STB    ,X
F735: 39          RTS

;----------------------------------------------------------------------------
; Create the 4 ghosts ($0E90,$0EB0,$0ED0,$0EF0) in the house.
;----------------------------------------------------------------------------
ghosts_init_f736:
F736: 96 96       LDA    <$96                   ; <$96=bonus stage flag
F738: 27 01       BEQ    $F73B
F73A: 39          RTS
F73B: CE 0E 90    LDU    #$0E90
F73E: 10 8E F7 64 LDY    #$F764
F742: C6 03       LDB    #$03
F744: E7 56       STB    -$A,U
F746: A6 A0       LDA    ,Y+
F748: A7 53       STA    -$D,U
F74A: AE A1       LDX    ,Y++
F74C: AF 4C       STX    $C,U
F74E: 8E F8 47    LDX    #$F847                 ; [function_address] ; -> ghost_anim_frame_f847
F751: AF C4       STX    ,U
F753: 8E 00 00    LDX    #$0000
F756: AF 4E       STX    $E,U
F758: 8E F0 FB    LDX    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
F75B: AF 44       STX    $4,U
F75D: 33 C8 20    LEAU   $20,U
F760: 5A          DECB
F761: 2A E1       BPL    $F744
F763: 39          RTS

ghosts_start_f770:
F770: 96 96       LDA    <$96                   ; <$96=bonus stage flag
F772: 27 01       BEQ    $F775
F774: 39          RTS
F775: CC F7 9A    LDD    #$F79A                 ; [function_address] ; -> ghost_task_f79a
F778: 20 03       BRA    set_ghosts_state_f77d

set_pacman_state_f77a:
F77A: FD 16 30    STD    pacman_object_1630

;----------------------------------------------------------------------------
; F77D: state PC of the 4 ghosts := D.  F77A: Pac-Man too.  F78D: runner of the 4 ghosts := D.  F78A: Pac-Man too.
;----------------------------------------------------------------------------
set_ghosts_state_f77d:
F77D: FD 0E F0    STD    $0EF0
F780: FD 0E D0    STD    $0ED0
F783: FD 0E B0    STD    $0EB0
F786: FD 0E 90    STD    $0E90
F789: 39          RTS

set_pacman_runner_f78a:
F78A: FD 16 34    STD    $1634

set_ghosts_runner_f78d:
F78D: FD 0E F4    STD    $0EF4
F790: FD 0E D4    STD    $0ED4
F793: FD 0E B4    STD    $0EB4
F796: FD 0E 94    STD    $0E94
F799: 39          RTS

;----------------------------------------------------------------------------
; Ghost task: wait for its release time (tables $F97E/$F986/$F98E), leave the house, chase loop.
;----------------------------------------------------------------------------
ghost_task_f79a:
F79A: 96 95       LDA    <$95                   ; <$95=ghost release table index
F79C: 48          ASLA
F79D: E6 56       LDB    -$A,U
F79F: 58          ASLB
F7A0: 8E F7 A5    LDX    #ghost_release_table_f7a5
F7A3: 6E 95       JMP    [B,X]                  ; [indirect_jump] [nb_entries=4]

ghost_release_table_f7a5:
	dc.w	ghost_chase_loop_f7d1
	dc.w	ghost_leave_house_f7c5
	dc.w	ghost_release_wait_a_f7ad
	dc.w	ghost_release_wait_b_f7bc

ghost_release_wait_a_f7ad:
F7AD: 8E F9 7E    LDX    #$F97E
F7B0: AE 86       LDX    A,X
F7B2: 9C 92       CMPX   <$92                   ; <$92=frames since level start
F7B4: 27 0F       BEQ    ghost_leave_house_f7c5
F7B6: CC 80 60    LDD    #$8060
F7B9: 7E F7 EF    JMP    ghost_chase_step_f7ef

ghost_release_wait_b_f7bc:
F7BC: 8E F9 86    LDX    #$F986
F7BF: AE 86       LDX    A,X
F7C1: 9C 92       CMPX   <$92                   ; <$92=frames since level start
F7C3: 26 F1       BNE    $F7B6

ghost_leave_house_f7c5:
F7C5: CC 00 1E    LDD    #$001E
F7C8: BD E2 BB    JSR    task_wait_init_e2bb
F7CB: BD F8 71    JSR    ghost_house_bob_frame_f871
F7CE: BD E2 C4    JSR    task_wait_e2c4

ghost_chase_loop_f7d1:
F7D1: BD E2 B4    JSR    task_yield_e2b4
F7D4: 96 95       LDA    <$95                   ; <$95=ghost release table index
F7D6: 48          ASLA
F7D7: 8E F9 8E    LDX    #$F98E
F7DA: AE 86       LDX    A,X
F7DC: E6 80       LDB    ,X+
F7DE: 10 AE 81    LDY    ,X++
F7E1: 27 07       BEQ    $F7EA
F7E3: 10 9C 92    CMPY   <$92                   ; <$92=frames since level start
F7E6: 25 F4       BCS    $F7DC
F7E8: 27 DB       BEQ    ghost_leave_house_f7c5
F7EA: E7 55       STB    -$B,U
F7EC: BD F9 C9    JSR    ghost_target_f9c9

ghost_chase_step_f7ef:
F7EF: BD FB 30    JSR    direction_to_target_fb30
F7F2: BD FB 54    JSR    direction_preference_fb54
F7F5: BD F8 01    JSR    ghost_select_speed_f801
F7F8: BD FA 33    JSR    ghost_move_fa33
F7FB: BD F8 47    JSR    ghost_anim_frame_f847
F7FE: 7E F6 54    JMP    ghost_check_catch_pacman_f654

;----------------------------------------------------------------------------
; Ghost speed: tunnel, normal, 'elroy' 1/2 (fewer items left).
;----------------------------------------------------------------------------
ghost_select_speed_f801:
F801: EC 4C       LDD    $C,U
F803: C1 78       CMPB   #$78
F805: 26 10       BNE    $F817
F807: 8B 20       ADDA   #$20
F809: 85 40       BITA   #$40
F80B: 26 0A       BNE    $F817
F80D: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F80F: B7 40 46    STA    $4046                  ; SOUND: ghost siren 1
F812: DC A6       LDD    <$A6                   ; <$A6=ghost speed tunnel
F814: ED 50       STD    -$10,U
F816: 39          RTS
F817: E6 56       LDB    -$A,U
F819: D1 97       CMPB   <$97                   ; <$97=elroy ghost index limit
F81B: 24 20       BCC    $F83D
F81D: 96 90       LDA    <$90                   ; <$90=fruits left
F81F: 9B 91       ADDA   <$91                   ; <$91=power pellets left
F821: 91 98       CMPA   <$98                   ; <$98=elroy threshold 1
F823: 22 18       BHI    $F83D
F825: 91 99       CMPA   <$99                   ; <$99=elroy threshold 2
F827: 22 0A       BHI    $F833
F829: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F82B: B7 40 4B    STA    $404B                  ; SOUND: ghost siren 3
F82E: DC A4       LDD    <$A4                   ; <$A4=ghost speed elroy 2
F830: ED 50       STD    -$10,U
F832: 39          RTS
F833: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F835: B7 40 47    STA    $4047                  ; SOUND: ghost siren 2
F838: DC A2       LDD    <$A2                   ; <$A2=ghost speed elroy 1
F83A: ED 50       STD    -$10,U
F83C: 39          RTS
F83D: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F83F: B7 40 46    STA    $4046                  ; SOUND: ghost siren 1
F842: DC A0       LDD    <$A0                   ; <$A0=ghost speed normal
F844: ED 50       STD    -$10,U
F846: 39          RTS

;----------------------------------------------------------------------------
; Ghost sprite frame / colour.
;----------------------------------------------------------------------------
ghost_anim_frame_f847:
F847: A6 56       LDA    -$A,U
F849: 8B 04       ADDA   #$04

ghost_anim_frame_colour_f84b:
F84B: A7 4B       STA    $B,U

ghost_anim_frame_nocolour_f84d:
F84D: 4F          CLRA
F84E: E6 53       LDB    -$D,U
F850: C1 01       CMPB   #$01
F852: 26 02       BNE    $F856
F854: 86 02       LDA    #$02
F856: A7 49       STA    $9,U
F858: 8E F8 6D    LDX    #$F86D                 ; NOT a function address: sprite code table $F86D
F85B: 96 81       LDA    <$81                   ; <$81=frame counter
F85D: 44          LSRA
F85E: 44          LSRA
F85F: 84 01       ANDA   #$01
F861: AB 85       ADDA   B,X
F863: F6 16 26    LDB    $1626
F866: 27 02       BEQ    $F86A
F868: 8B 06       ADDA   #$06
F86A: A7 4A       STA    $A,U
F86C: 39          RTS

table_ghost_sprite_codes_f86d:
	dc.b	$26,$24,$28,$24                           ; DATA: ghost sprite codes per direction (was disassembled as BNE/BVC)

ghost_house_bob_frame_f871:
F871: A6 56       LDA    -$A,U
F873: 8B 04       ADDA   #$04
F875: A7 4B       STA    $B,U
F877: BD F6 54    JSR    ghost_check_catch_pacman_f654
F87A: D6 81       LDB    <$81                   ; <$81=frame counter
F87C: C4 03       ANDB   #$03
F87E: 8E F8 99    LDX    #$F899
F881: 3A          ABX
F882: A6 84       LDA    ,X
F884: E6 53       LDB    -$D,U
F886: 54          LSRB
F887: 24 0C       BCC    $F895
F889: 84 02       ANDA   #$02
F88B: A7 49       STA    $9,U
F88D: A6 84       LDA    ,X
F88F: 84 01       ANDA   #$01
F891: 8B 24       ADDA   #$24
F893: 20 CE       BRA    $F863
F895: 8B 26       ADDA   #$26
F897: 20 CA       BRA    $F863

ghost_eyes_step_f89d:
F89D: BD F9 C9    JSR    ghost_target_f9c9
F8A0: BD FB 30    JSR    direction_to_target_fb30
F8A3: 88 04       EORA   #$04
F8A5: BD FB 54    JSR    direction_preference_fb54
F8A8: DC A8       LDD    <$A8                   ; <$A8=ghost eyes speed
F8AA: ED 50       STD    -$10,U
F8AC: BD FA 33    JSR    ghost_move_fa33
F8AF: 8D 14       BSR    ghost_eyes_sound_f8c5
F8B1: FC 11 2A    LDD    $112A
F8B4: 10 83 00 48 CMPD   #$0048
F8B8: 25 01       BCS    $F8BB
F8BA: 39          RTS
F8BB: C5 08       BITB   #$08
F8BD: 27 01       BEQ    $F8C0
F8BF: 39          RTS
F8C0: C6 03       LDB    #$03
F8C2: E7 4B       STB    $B,U
F8C4: 39          RTS

ghost_eyes_sound_f8c5:
F8C5: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F8C7: B7 40 48    STA    $4048                  ; SOUND: ghost eyes

ghost_eyes_frame_f8ca:
F8CA: 96 81       LDA    <$81                   ; <$81=frame counter
F8CC: 44          LSRA
F8CD: 44          LSRA
F8CE: 84 01       ANDA   #$01
F8D0: 8B 30       ADDA   #$30
F8D2: C6 08       LDB    #$08
F8D4: ED 4A       STD    $A,U
F8D6: 39          RTS

;----------------------------------------------------------------------------
; Frightened ghost task (after a power pellet); eaten -> 200/400/800/1600, eyes go home.
;----------------------------------------------------------------------------
ghost_frightened_task_f8d7:
F8D7: A6 53       LDA    -$D,U
F8D9: 88 02       EORA   #$02
F8DB: A7 53       STA    -$D,U
F8DD: BD E2 B4    JSR    task_yield_e2b4
F8E0: 8D BB       BSR    ghost_eyes_step_f89d
F8E2: BD F6 AC    JSR    collision_with_pacman_f6ac
F8E5: 81 08       CMPA   #$08
F8E7: 25 11       BCS    $F8FA
F8E9: FC 11 2A    LDD    $112A
F8EC: 27 01       BEQ    $F8EF
F8EE: 39          RTS
F8EF: 7E F7 D1    JMP    ghost_chase_loop_f7d1

F8FA: 6F 4B       CLR    $B,U
F8FC: 0F 8C       CLR    <$8C                   ; <$8C=bonus stage timer on
F8FE: CC F1 01    LDD    #$f101                 ; [function_address] ; -> runner_draw_sprite_f101
F901: BD F7 8A    JSR    set_pacman_runner_f78a
F904: CC E2 BA    LDD    #$e2ba                 ; [function_address] ; -> task_nop_rts_e2ba
F907: FD 11 2C    STD    $112C
F90A: CC F0 DE    LDD    #$f0de                 ; [function_address] ; -> runner_resume_f0de
F90D: ED 44       STD    $4,U
F90F: CE 16 30    LDU    #$1630
F912: CC 00 3C    LDD    #$003C
F915: A7 49       STA    $9,U
F917: E7 4B       STB    $B,U
F919: 96 8A       LDA    <$8A                   ; <$8A=ghosts eaten in a row
F91B: 8B 34       ADDA   #$34
F91D: A7 4A       STA    $A,U
F91F: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
F921: B7 40 4D    STA    $404D                  ; SOUND: ghost eaten
F924: 96 8A       LDA    <$8A                   ; <$8A=ghosts eaten in a row
F926: 48          ASLA
F927: 8E F8 F2    LDX    #$F8F2
F92A: EC 86       LDD    A,X
F92C: BD FD 6B    JSR    add_score_fd6b
F92F: 0C 8A       INC    <$8A                   ; <$8A=ghosts eaten in a row
F931: CC 00 3C    LDD    #$003C
F934: BD E2 BB    JSR    task_wait_init_e2bb
F937: BD E2 C4    JSR    task_wait_e2c4
F93A: 86 01       LDA    #$01
F93C: 97 8C       STA    <$8C                   ; <$8C=bonus stage timer on
F93E: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
F941: BD F7 8A    JSR    set_pacman_runner_f78a
F944: CC F0 DE    LDD    #$f0de                 ; [function_address] ; -> runner_resume_f0de
F947: FD 11 2C    STD    $112C
F94A: BD E2 B4    JSR    task_yield_e2b4
F94D: 7F 11 70    CLR    $1170
F950: 7F 11 78    CLR    $1178
F953: CC 80 64    LDD    #$8064
F956: BD FB 30    JSR    direction_to_target_fb30
F959: BD FB 54    JSR    direction_preference_fb54
F95C: CC 03 00    LDD    #$0300
F95F: ED 50       STD    -$10,U
F961: BD FA 33    JSR    ghost_move_fa33
F964: 86 0A       LDA    #$0A
F966: BD F8 4B    JSR    ghost_anim_frame_colour_f84b
F969: CC 5A 3C    LDD    #$5A3C
F96C: B7 11 70    STA    $1170
F96F: F7 11 78    STB    $1178
F972: CC 80 64    LDD    #$8064
F975: BD F6 AF    JSR    distance_to_pacman_f6af
F978: 25 01       BCS    $F97B
F97A: 39          RTS
F97B: 7E F7 D1    JMP    ghost_chase_loop_f7d1

;----------------------------------------------------------------------------
; Ghost target: house exit / blinky = Pac-Man / pinky ahead of Pac-Man / inky / clyde (table $F9F0).
;----------------------------------------------------------------------------
ghost_target_f9c9:
F9C9: EC 4C       LDD    $C,U
F9CB: C1 50       CMPB   #$50
F9CD: 26 0F       BNE    $F9DE
F9CF: 80 78       SUBA   #$78
F9D1: 81 11       CMPA   #$11
F9D3: 24 09       BCC    $F9DE
F9D5: A6 53       LDA    -$D,U
F9D7: 44          LSRA
F9D8: 24 04       BCC    $F9DE
F9DA: CC 80 3C    LDD    #$803C
F9DD: 39          RTS
F9DE: A6 56       LDA    -$A,U
F9E0: 48          ASLA
F9E1: E6 55       LDB    -$B,U
F9E3: 26 05       BNE    $F9EA
F9E5: 8E F9 F0    LDX    #ghost_target_table_f9f0
F9E8: 6E 96       JMP    [A,X]                  ; [indirect_jump] [nb_entries=5]
F9EA: 8E F4 88    LDX    #$F488
F9ED: EC 86       LDD    A,X
F9EF: 39          RTS

ghost_target_table_f9f0:
	dc.w	target_blinky_f9f8
	dc.w	target_pinky_f9fc
	dc.w	target_inky_fa16
	dc.w	target_clyde_fa22
	dc.w	target_frightened_fc16

target_blinky_f9f8:
F9F8: FC 16 3C    LDD    pacman_y_163c
F9FB: 39          RTS

target_pinky_f9fc:
F9FC: B6 16 23    LDA    $1623
F9FF: 84 7F       ANDA   #$7F
FA01: 48          ASLA
FA02: 8E FA 0E    LDX    #$FA0E
FA05: EC 86       LDD    A,X
FA07: BB 16 3C    ADDA   pacman_y_163c
FA0A: FB 16 3D    ADDB   $163D
FA0D: 39          RTS

target_inky_fa16:
FA16: FC 16 3C    LDD    pacman_y_163c
FA19: 48          ASLA
FA1A: B0 0E FC    SUBA   $0EFC
FA1D: 58          ASLB
FA1E: F0 0E FD    SUBB   $0EFD
FA21: 39          RTS

target_clyde_fa22:
FA22: BD F6 AC    JSR    collision_with_pacman_f6ac
FA25: 81 21       CMPA   #$21
FA27: FC 16 3C    LDD    pacman_y_163c
FA2A: 25 01       BCS    $FA2D
FA2C: 39          RTS
FA2D: BD FB 90    JSR    random_fb90
FA30: DC EC       LDD    <$EC                   ; <$EC=random seed
FA32: 39          RTS

;----------------------------------------------------------------------------
; Move a ghost by its speed, choosing the direction at each tile.
;----------------------------------------------------------------------------
ghost_move_fa33:
FA33: AE 4E       LDX    $E,U
FA35: EC 50       LDD    -$10,U
FA37: 30 8B       LEAX   D,X
FA39: AF 4E       STX    $E,U
FA3B: A6 4E       LDA    $E,U
FA3D: 27 08       BEQ    $FA47
FA3F: 8D 20       BSR    ghost_choose_direction_fa61
FA41: 8D 05       BSR    object_step_one_pixel_fa48
FA43: 6A 4E       DEC    $E,U
FA45: 26 F8       BNE    $FA3F
FA47: 39          RTS

;----------------------------------------------------------------------------
; Move object U one pixel in direction -$D,U: 0 = x-1, 1 = y-1, 2 = x+1, 3 = y+1 (bit 7 = blocked, no move).
;----------------------------------------------------------------------------
object_step_one_pixel_fa48:
FA48: A6 53       LDA    -$D,U
FA4A: 2A 01       BPL    $FA4D
FA4C: 39          RTS
FA4D: 27 09       BEQ    $FA58
FA4F: 81 02       CMPA   #$02
FA51: 25 08       BCS    $FA5B
FA53: 27 09       BEQ    $FA5E
FA55: 6C 4C       INC    $C,U
FA57: 39          RTS
FA58: 6A 4D       DEC    $D,U
FA5A: 39          RTS
FA5B: 6A 4C       DEC    $C,U
FA5D: 39          RTS
FA5E: 6C 4D       INC    $D,U
FA60: 39          RTS

ghost_choose_direction_fa61:
FA61: E6 4C       LDB    $C,U
FA63: C0 1C       SUBB   #$1C
FA65: BD FB AA    JSR    div_by_20_fbaa
FA68: 27 01       BEQ    $FA6B
FA6A: 39          RTS
FA6B: D7 FE       STB    <$FE
FA6D: E6 4D       LDB    $D,U
FA6F: C0 14       SUBB   #$14
FA71: BD FB AA    JSR    div_by_20_fbaa
FA74: 27 01       BEQ    $FA77
FA76: 39          RTS
FA77: D7 FF       STB    <$FF
FA79: 8D 31       BSR    maze_get_exits_faac
FA7B: BD FA FB    JSR    maze_block_up_in_tunnel_fafb
FA7E: BD FB 09    JSR    maze_forbidden_up_fb09
FA81: A6 53       LDA    -$D,U
FA83: 88 02       EORA   #$02
FA85: C6 04       LDB    #$04
FA87: DD F8       STD    <$F8                   ; <$F8=temp / loop counter
FA89: A6 52       LDA    -$E,U
FA8B: 84 03       ANDA   #$03
FA8D: A7 53       STA    -$D,U
FA8F: 91 F8       CMPA   <$F8                   ; <$F8=temp / loop counter
FA91: 27 05       BEQ    $FA98
FA93: 8D 10       BSR    test_exit_bit_faa5
FA95: 25 01       BCS    $FA98
FA97: 39          RTS
FA98: 64 52       LSR    -$E,U
FA9A: 64 52       LSR    -$E,U
FA9C: 0A F9       DEC    <$F9
FA9E: 26 E9       BNE    $FA89
FAA0: 96 F8       LDA    <$F8                   ; <$F8=temp / loop counter
FAA2: A7 53       STA    -$D,U
FAA4: 39          RTS

test_exit_bit_faa5:
FAA5: E6 54       LDB    -$C,U
FAA7: 54          LSRB
FAA8: 4A          DECA
FAA9: 2A FC       BPL    $FAA7
FAAB: 39          RTS

;----------------------------------------------------------------------------
; Maze exits of the current tile -> -$C,U (4 bits), from the tile codes / $1160.
;----------------------------------------------------------------------------
maze_get_exits_faac:
FAAC: A6 53       LDA    -$D,U
FAAE: 2A 01       BPL    $FAB1
FAB0: 39          RTS
FAB1: 6F 54       CLR    -$C,U
FAB3: CC 08 00    LDD    #$0800
FAB6: 8D 0D       BSR    maze_test_exit_fac5
FAB8: CC 00 08    LDD    #$0008
FABB: 8D 08       BSR    maze_test_exit_fac5
FABD: CC F7 00    LDD    #$F700
FAC0: 8D 03       BSR    maze_test_exit_fac5
FAC2: CC 00 F7    LDD    #$00F7

maze_test_exit_fac5:
FAC5: 0F FA       CLR    <$FA
FAC7: AB 4C       ADDA   $C,U
FAC9: EB 4D       ADDB   $D,U
FACB: 44          LSRA
FACC: 44          LSRA
FACD: 44          LSRA
FACE: 09 FA       ROL    <$FA
FAD0: 44          LSRA
FAD1: 56          RORB
FAD2: 44          LSRA
FAD3: 56          RORB
FAD4: 44          LSRA
FAD5: 56          RORB
FAD6: 09 FA       ROL    <$FA
FAD8: 8E 00 00    LDX    #$0000
FADB: A6 8B       LDA    D,X
FADD: 8B 40       ADDA   #$40
FADF: 24 0E       BCC    $FAEF
FAE1: 44          LSRA
FAE2: 8E 11 60    LDX    #$1160
FAE5: A6 86       LDA    A,X
FAE7: D6 FA       LDB    <$FA
FAE9: 25 07       BCS    $FAF2
FAEB: 48          ASLA
FAEC: 5A          DECB
FAED: 2A FC       BPL    $FAEB
FAEF: 69 54       ROL    -$C,U
FAF1: 39          RTS
FAF2: C8 03       EORB   #$03
FAF4: 44          LSRA
FAF5: 5A          DECB
FAF6: 2A FC       BPL    $FAF4
FAF8: 69 54       ROL    -$C,U
FAFA: 39          RTS

maze_block_up_in_tunnel_fafb:
FAFB: 96 FE       LDA    <$FE
FAFD: 81 0B       CMPA   #$0B
FAFF: 24 01       BCC    $FB02
FB01: 39          RTS
FB02: A6 54       LDA    -$C,U
FB04: 8A 05       ORA    #$05
FB06: A7 54       STA    -$C,U
FB08: 39          RTS

maze_forbidden_up_fb09:
FB09: 9E FE       LDX    <$FE
FB0B: 8C 02 09    CMPX   #$0209
FB0E: 26 07       BNE    $FB17
FB10: A6 54       LDA    -$C,U
FB12: 8A 02       ORA    #$02
FB14: A7 54       STA    -$C,U
FB16: 39          RTS
FB17: 8C 05 05    CMPX   #$0505
FB1A: 26 07       BNE    $FB23
FB1C: A6 54       LDA    -$C,U
FB1E: 8A 04       ORA    #$04
FB20: A7 54       STA    -$C,U
FB22: 39          RTS
FB23: 8C 08 09    CMPX   #$0809
FB26: 27 01       BEQ    $FB29
FB28: 39          RTS
FB29: A6 54       LDA    -$C,U
FB2B: 8A 08       ORA    #$08
FB2D: A7 54       STA    -$C,U
FB2F: 39          RTS

direction_to_target_fb30:
FB30: 8D 2A       BSR    tunnel_target_fix_fb5c
FB32: A0 4C       SUBA   $C,U
FB34: 06 FA       ROR    <$FA
FB36: 2A 01       BPL    $FB39
FB38: 40          NEGA
FB39: 97 FB       STA    <$FB
FB3B: E0 4D       SUBB   $D,U
FB3D: 06 FA       ROR    <$FA
FB3F: 2A 01       BPL    $FB42
FB41: 50          NEGB
FB42: 4F          CLRA
FB43: D1 FB       CMPB   <$FB
FB45: 49          ROLA
FB46: 09 FA       ROL    <$FA
FB48: 24 02       BCC    $FB4C
FB4A: 88 03       EORA   #$03
FB4C: 09 FA       ROL    <$FA
FB4E: 25 01       BCS    $FB51
FB50: 39          RTS
FB51: 88 07       EORA   #$07
FB53: 39          RTS

direction_preference_fb54:
FB54: 8E FB 88    LDX    #$FB88
FB57: A6 86       LDA    A,X
FB59: A7 52       STA    -$E,U
FB5B: 39          RTS

tunnel_target_fix_fb5c:
FB5C: C1 78       CMPB   #$78
FB5E: 27 01       BEQ    $FB61
FB60: 39          RTS
FB61: 81 1D       CMPA   #$1D
FB63: 24 0F       BCC    $FB74
FB65: 34 02       PSHS   A
FB67: B6 16 23    LDA    $1623
FB6A: 85 02       BITA   #$02
FB6C: 35 02       PULS   A
FB6E: 26 01       BNE    $FB71
FB70: 39          RTS
FB71: 86 DA       LDA    #$DA
FB73: 39          RTS
FB74: 81 E4       CMPA   #$E4
FB76: 24 01       BCC    $FB79
FB78: 39          RTS
FB79: 34 02       PSHS   A
FB7B: B6 16 23    LDA    $1623
FB7E: 85 02       BITA   #$02
FB80: 35 02       PULS   A
FB82: 27 01       BEQ    $FB85
FB84: 39          RTS
FB85: 86 26       LDA    #$26
FB87: 39          RTS

;----------------------------------------------------------------------------
; Random number generator (seed <$EC/<$ED).
;----------------------------------------------------------------------------
random_fb90:
FB90: 86 05       LDA    #$05
FB92: D6 ED       LDB    <$ED                   ; <$ED=random seed lo
FB94: 3D          MUL
FB95: 5C          INCB
FB96: 43          COMA
FB97: 96 EC       LDA    <$EC                   ; <$EC=random seed
FB99: 84 90       ANDA   #$90
FB9B: 27 05       BEQ    $FBA2
FB9D: 88 90       EORA   #$90
FB9F: 27 01       BEQ    $FBA2
FBA1: 4F          CLRA
FBA2: 96 EC       LDA    <$EC                   ; <$EC=random seed
FBA4: 49          ROLA
FBA5: DD EC       STD    <$EC                   ; <$EC=random seed
FBA7: 9B ED       ADDA   <$ED                   ; <$ED=random seed lo
FBA9: 39          RTS

;----------------------------------------------------------------------------
; B = B / 20, A = remainder (Z=1 if on a tile centre).
;----------------------------------------------------------------------------
div_by_20_fbaa:
FBAA: 86 14       LDA    #$14
FBAC: 97 EE       STA    <$EE
FBAE: 86 08       LDA    #$08
FBB0: 97 EF       STA    <$EF
FBB2: 4F          CLRA
FBB3: 58          ASLB
FBB4: 49          ROLA
FBB5: 91 EE       CMPA   <$EE
FBB7: 25 03       BCS    $FBBC
FBB9: 90 EE       SUBA   <$EE
FBBB: 5C          INCB
FBBC: 0A EF       DEC    <$EF
FBBE: 26 F3       BNE    $FBB3
FBC0: 4D          TSTA
FBC1: 39          RTS

;----------------------------------------------------------------------------
; When 22 items are left: create the bonus target and the two star symbols.
;----------------------------------------------------------------------------
check_bonus_items_fbc2:
FBC2: 96 90       LDA    <$90                   ; <$90=fruits left
FBC4: 9B 91       ADDA   <$91                   ; <$91=power pellets left
FBC6: 81 16       CMPA   #$16
FBC8: 27 01       BEQ    $FBCB
FBCA: 39          RTS
FBCB: CC FB DE    LDD    #$FBDE                 ; [function_address] ; -> bonus_target_task_fbde
FBCE: FD 16 10    STD    $1610
FBD1: CC FC DF    LDD    #$FCDF                 ; [function_address] ; -> star_symbol_left_task_fcdf
FBD4: FD 16 70    STD    $1670
FBD7: CC FC D8    LDD    #$FCD8                 ; [function_address] ; -> star_symbol_right_task_fcd8
FBDA: FD 16 50    STD    $1650
FBDD: 39          RTS

;----------------------------------------------------------------------------
; Bonus target object: eaten while the star symbols match -> big bonus.
;----------------------------------------------------------------------------
bonus_target_task_fbde:
FBDE: CC 80 8C    LDD    #$808C
FBE1: ED 4C       STD    $C,U
FBE3: 6F 49       CLR    $9,U
FBE5: CC 43 28    LDD    #$4328
FBE8: ED 4A       STD    $A,U
FBEA: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
FBED: ED 44       STD    $4,U
FBEF: CC 00 78    LDD    #$0078
FBF2: BD E2 BB    JSR    task_wait_init_e2bb
FBF5: BD FC CD    JSR    bonus_blink_fccd
FBF8: BD F6 AC    JSR    collision_with_pacman_f6ac
FBFB: 25 37       BCS    $FC34
FBFD: BD E2 C4    JSR    task_wait_e2c4
FC00: CE 16 50    LDU    #$1650
FC03: 96 2A       LDA    <$2A
FC05: 85 01       BITA   #$01
FC07: 26 05       BNE    $FC0E
FC09: 96 10       LDA    <$10                   ; <$10=bonus item type of the level
FC0B: BD FD 28    JSR    star_symbol_set_fd28
FC0E: CC F1 01    LDD    #$f101                 ; [function_address] ; -> runner_draw_sprite_f101
FC11: ED 44       STD    $4,U
FC13: CC 01 E0    LDD    #$01E0

target_frightened_fc16:
FC16: BD E2 BB    JSR    task_wait_init_e2bb
FC19: BD FC CD    JSR    bonus_blink_fccd
FC1C: BD F6 AC    JSR    collision_with_pacman_f6ac
FC1F: 25 13       BCS    $FC34
FC21: BD E2 C4    JSR    task_wait_e2c4
FC24: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
FC27: FD 16 14    STD    $1614
FC2A: FD 16 54    STD    $1654
FC2D: FD 16 74    STD    $1674
FC30: BD E2 B4    JSR    task_yield_e2b4
FC33: 39          RTS
FC34: CC F0 EF    LDD    #$F0EF                 ; [function_address] ; -> runner_hide_sprite_f0ef
FC37: ED 44       STD    $4,U
FC39: CC F1 01    LDD    #$f101                 ; [function_address] ; -> runner_draw_sprite_f101
FC3C: BD F7 8A    JSR    set_pacman_runner_f78a
FC3F: FD 16 54    STD    $1654
FC42: FD 16 74    STD    $1674
FC45: CC E2 BA    LDD    #$e2ba                 ; [function_address] ; -> task_nop_rts_e2ba
FC48: FD 11 2C    STD    $112C
FC4B: 0F 8C       CLR    <$8C                   ; <$8C=bonus stage timer on
FC4D: 7F 40 4E    CLR    $404E
FC50: 8E 00 3C    LDX    #$003C
FC53: CE 40 4F    LDU    #$404F
FC56: D6 1A       LDB    <$1A                   ; <$1A=levels played (max 12)
FC58: C4 FC       ANDB   #$FC
FC5A: B6 16 40    LDA    $1640
FC5D: B1 16 60    CMPA   $1660
FC60: 26 0D       BNE    $FC6F
FC62: 8E 00 B4    LDX    #$00B4
FC65: 33 41       LEAU   $1,U
FC67: C6 10       LDB    #$10
FC69: 91 10       CMPA   <$10                   ; <$10=bonus item type of the level
FC6B: 26 02       BNE    $FC6F
FC6D: CB 04       ADDB   #$04
FC6F: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
FC71: A7 C4       STA    ,U
FC73: 34 10       PSHS   X
FC75: 8E FC B5    LDX    #$FCB5
FC78: 3A          ABX
FC79: CE 16 30    LDU    #$1630
FC7C: EC 84       LDD    ,X
FC7E: ED 49       STD    $9,U
FC80: 86 3C       LDA    #$3C
FC82: A7 4B       STA    $B,U
FC84: EC 02       LDD    $2,X
FC86: BD FD 6B    JSR    add_score_fd6b
FC89: 35 06       PULS   D
FC8B: BD E2 BB    JSR    task_wait_init_e2bb
FC8E: BD E2 C4    JSR    task_wait_e2c4
FC91: CC F0 E5    LDD    #$f0e5                 ; [function_address] ; -> runner_kill_object_f0e5
FC94: FD 16 54    STD    $1654
FC97: FD 16 74    STD    $1674
FC9A: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
FC9D: FD 16 34    STD    $1634
FCA0: 0D 96       TST    <$96                   ; <$96=bonus stage flag
FCA2: 26 03       BNE    $FCA7
FCA4: BD F7 8D    JSR    set_ghosts_runner_f78d
FCA7: CC F0 DE    LDD    #$f0de                 ; [function_address] ; -> runner_resume_f0de
FCAA: FD 11 2C    STD    $112C
FCAD: 86 01       LDA    #$01
FCAF: 97 8C       STA    <$8C                   ; <$8C=bonus stage timer on
FCB1: BD E2 B4    JSR    task_yield_e2b4
FCB4: 39          RTS

bonus_blink_fccd:
FCCD: 96 81       LDA    <$81                   ; <$81=frame counter
FCCF: 84 08       ANDA   #$08
FCD1: 27 02       BEQ    $FCD5
FCD3: 86 28       LDA    #$28
FCD5: A7 4B       STA    $B,U
FCD7: 39          RTS

;----------------------------------------------------------------------------
; Star symbols (slot machine) left/right: cycle through the item icons.
;----------------------------------------------------------------------------
star_symbol_right_task_fcd8:
FCD8: 8E 94 8C    LDX    #$948C
FCDB: C6 0A       LDB    #$0A
FCDD: 20 05       BRA    $FCE4

star_symbol_left_task_fcdf:
FCDF: 8E 6C 8C    LDX    #$6C8C
FCE2: C6 0F       LDB    #$0F
FCE4: AF 4C       STX    $C,U
FCE6: E7 51       STB    -$F,U
FCE8: BD FB 90    JSR    random_fb90
FCEB: 84 07       ANDA   #$07
FCED: 9B 10       ADDA   <$10                   ; <$10=bonus item type of the level
FCEF: 81 10       CMPA   #$10
FCF1: 25 02       BCS    $FCF5
FCF3: 80 10       SUBA   #$10
FCF5: A7 50       STA    -$10,U
FCF7: 96 10       LDA    <$10                   ; <$10=bonus item type of the level
FCF9: 8B 08       ADDA   #$08
FCFB: 81 10       CMPA   #$10
FCFD: 25 02       BCS    $FD01
FCFF: 80 10       SUBA   #$10
FD01: E6 51       LDB    -$F,U
FD03: ED 55       STD    -$B,U
FD05: 6F 49       CLR    $9,U
FD07: 8D 21       BSR    star_symbol_draw_fd2a
FD09: CC F0 FB    LDD    #$f0fb                 ; [function_address] ; -> runner_resume_and_draw_f0fb
FD0C: ED 44       STD    $4,U
FD0E: BD E2 B4    JSR    task_yield_e2b4
FD11: 6A 51       DEC    -$F,U
FD13: 27 01       BEQ    $FD16
FD15: 39          RTS
FD16: A6 56       LDA    -$A,U
FD18: A7 51       STA    -$F,U
FD1A: A6 50       LDA    -$10,U
FD1C: 4C          INCA
FD1D: 81 10       CMPA   #$10
FD1F: 26 01       BNE    $FD22
FD21: 4F          CLRA
FD22: A1 55       CMPA   -$B,U
FD24: 26 02       BNE    star_symbol_set_fd28
FD26: 96 10       LDA    <$10                   ; <$10=bonus item type of the level

star_symbol_set_fd28:
FD28: A7 50       STA    -$10,U

star_symbol_draw_fd2a:
FD2A: A6 50       LDA    -$10,U
FD2C: 8B 44       ADDA   #$44
FD2E: E6 50       LDB    -$10,U
FD30: CB 10       ADDB   #$10
FD32: ED 4A       STD    $A,U
FD34: 96 8B       LDA    <$8B                   ; <$8B=game sounds enabled (0 in attract)
FD36: B7 40 4E    STA    $404E                  ; SOUND: star symbols
FD39: 39          RTS

;----------------------------------------------------------------------------
; Task: do nothing (counter cleared).
;----------------------------------------------------------------------------
task_idle_fd3a:
FD3A: CC 00 00    LDD    #$0000
FD3D: ED 42       STD    $2,U
FD3F: BD E2 B4    JSR    task_yield_e2b4
FD42: 39          RTS

;----------------------------------------------------------------------------
; Power pellet eaten: ghosts frightened, slot 5 = frightened_timer_task_fd53.
;----------------------------------------------------------------------------
power_pellet_eaten_fd43:
FD43: CC F8 D7    LDD    #$F8D7                 ; [function_address] ; -> ghost_frightened_task_f8d7
FD46: BD F7 7D    JSR    set_ghosts_state_f77d
FD49: 4F          CLRA
FD4A: 97 8A       STA    <$8A                   ; <$8A=ghosts eaten in a row
FD4C: CC FD 53    LDD    #$FD53                 ; [function_address] ; -> frightened_timer_task_fd53
FD4F: FD 11 28    STD    task_slot5_1128
FD52: 39          RTS

frightened_timer_task_fd53:
FD53: DC 9C       LDD    <$9C                   ; <$9C=frightened duration
FD55: 27 E3       BEQ    task_idle_fd3a
FD57: 7D 16 26    TST    $1626
FD5A: 27 03       BEQ    $FD5F
FD5C: FD 16 32    STD    $1632
FD5F: BD E2 BB    JSR    task_wait_init_e2bb
FD62: 96 96       LDA    <$96                   ; <$96=bonus stage flag
FD64: 27 01       BEQ    $FD67
FD66: 39          RTS
FD67: BD E2 C4    JSR    task_wait_e2c4
FD6A: 39          RTS

;----------------------------------------------------------------------------
; Add D (BCD) to the current score if <$8B (not in attract), request the
; score redraw (slot 3), extra life check (<$04/<$05, every <$D6/<$D7).
;----------------------------------------------------------------------------
add_score_fd6b:
FD6B: 0D 8B       TST    <$8B                   ; <$8B=game sounds enabled (0 in attract)
FD6D: 26 01       BNE    $FD70
FD6F: 39          RTS
FD70: 1E 89       EXG    A,B
FD72: 9B 02       ADDA   <$02                   ; <$02=score low
FD74: 19          DAA
FD75: 97 02       STA    <$02                   ; <$02=score low
FD77: 1F 98       TFR    B,A
FD79: 99 01       ADCA   <$01                   ; <$01=score mid
FD7B: 19          DAA
FD7C: 97 01       STA    <$01                   ; <$01=score mid
FD7E: 96 00       LDA    <$00                   ; <$00=score (3 BCD bytes, current player)
FD80: 89 00       ADCA   #$00
FD82: 19          DAA
FD83: 97 00       STA    <$00                   ; <$00=score (3 BCD bytes, current player)
FD85: CC FD CC    LDD    #$FDCC                 ; [function_address] ; slot 3 := score display ; -> score_display_task_fdcc
FD88: FD 11 18    STD    task_slot3_1118
FD8B: 96 06       LDA    <$06                   ; <$06=extra lives awarded
FD8D: 91 CF       CMPA   <$CF                   ; <$CF=bonus life setting
FD8F: 26 01       BNE    $FD92
FD91: 39          RTS
FD92: 9E 00       LDX    <$00                   ; <$00=score (3 BCD bytes, current player)
FD94: 9C 04       CMPX   <$04                   ; <$04=next extra-life score
FD96: 24 01       BCC    $FD99
FD98: 39          RTS
FD99: 96 06       LDA    <$06                   ; <$06=extra lives awarded
FD9B: 26 05       BNE    $FDA2
FD9D: 8E 00 00    LDX    #$0000
FDA0: 9F 04       STX    <$04                   ; <$04=next extra-life score
FDA2: 4C          INCA
FDA3: 81 FF       CMPA   #$FF
FDA5: 27 02       BEQ    $FDA9
FDA7: 97 06       STA    <$06                   ; <$06=extra lives awarded
FDA9: 96 05       LDA    <$05                   ; <$05=next extra-life score lo
FDAB: 9B D7       ADDA   <$D7
FDAD: 19          DAA
FDAE: 97 05       STA    <$05                   ; <$05=next extra-life score lo
FDB0: 96 04       LDA    <$04                   ; <$04=next extra-life score
FDB2: 99 D6       ADCA   <$D6                   ; <$D6=extra life every (BCD)
FDB4: 19          DAA
FDB5: 97 04       STA    <$04                   ; <$04=next extra-life score
FDB7: 24 05       BCC    $FDBE
FDB9: CC FF FF    LDD    #$FFFF
FDBC: DD 04       STD    <$04                   ; <$04=next extra-life score
FDBE: 86 01       LDA    #$01
FDC0: B7 40 54    STA    $4054                  ; SOUND: extra life
FDC3: 0C 07       INC    <$07                   ; <$07=lives left
FDC5: 26 02       BNE    $FDC9
FDC7: 0A 07       DEC    <$07                   ; <$07=lives left
FDC9: 7E EE 09    JMP    draw_lives_ee09

;----------------------------------------------------------------------------
; Slot 3 task: high score update and redraw of the scores (once, then idle).
;----------------------------------------------------------------------------
score_display_task_fdcc:
FDCC: BD FE 55    JSR    update_hiscore_fe55
FDCF: 8E 10 87    LDX    #$1087
FDD2: CE 03 F4    LDU    #$03F4
FDD5: 8D 22       BSR    print_score_fdf9
FDD7: 8D 04       BSR    draw_player_scores_fddd
FDD9: BD E2 B4    JSR    task_yield_e2b4
FDDC: 39          RTS

draw_player_scores_fddd:
FDDD: 8E 10 00    LDX    #$1000
FDE0: CE 10 40    LDU    #$1040
FDE3: 0D 84       TST    <$84                   ; <$84=current player (0/1)
FDE5: 27 02       BEQ    $FDE9
FDE7: 1E 13       EXG    X,U
FDE9: 34 40       PSHS   U
FDEB: CE 03 FD    LDU    #$03FD
FDEE: 8D 09       BSR    print_score_fdf9
FDF0: 35 10       PULS   X
FDF2: CE 03 EA    LDU    #$03EA
FDF5: 0D 82       TST    <$82                   ; <$82=2-player game flag
FDF7: 27 0B       BEQ    clear_score_fe04

print_score_fdf9:
FDF9: 10 8E 05 03 LDY    #$0503
FDFD: 8D 19       BSR    print_bcd_vert_fe18
FDFF: 86 30       LDA    #$30
FE01: A7 C4       STA    ,U
FE03: 39          RTS

clear_score_fe04:
FE04: CC 20 07    LDD    #$2007
FE07: A7 C4       STA    ,U
FE09: 33 5F       LEAU   -$1,U
FE0B: 5A          DECB
FE0C: 26 F9       BNE    $FE07
FE0E: 39          RTS

;----------------------------------------------------------------------------
; Write A to B tiles, step -$20 (horizontal line).
;----------------------------------------------------------------------------
fill_row_fe0f:
FE0F: A7 C4       STA    ,U
FE11: 33 C8 E0    LEAU   -$20,U
FE14: 5A          DECB
FE15: 26 F8       BNE    fill_row_fe0f
FE17: 39          RTS

print_bcd_vert_fe18:
FE18: C6 FF       LDB    #$FF
FE1A: 20 02       BRA    $FE1E

;----------------------------------------------------------------------------
; Print BCD digits from (X), Y = (leading blanks, bytes) at U, step -$20. FE18: step -1.
;----------------------------------------------------------------------------
print_bcd_fe1c:
FE1C: C6 E0       LDB    #$E0
FE1E: 10 9F EE    STY    <$EE
FE21: A6 84       LDA    ,X
FE23: 8D 0D       BSR    bcd_high_to_ascii_fe32
FE25: 8D 1B       BSR    put_digit_zero_blank_fe42
FE27: A6 80       LDA    ,X+
FE29: 8D 0B       BSR    bcd_low_to_ascii_fe36
FE2B: 8D 15       BSR    put_digit_zero_blank_fe42
FE2D: 0A EF       DEC    <$EF
FE2F: 26 F0       BNE    $FE21
FE31: 39          RTS

bcd_high_to_ascii_fe32:
FE32: 44          LSRA
FE33: 44          LSRA
FE34: 44          LSRA
FE35: 44          LSRA

bcd_low_to_ascii_fe36:
FE36: 84 0F       ANDA   #$0F
FE38: 8B 30       ADDA   #$30
FE3A: 81 3A       CMPA   #$3A
FE3C: 24 01       BCC    $FE3F
FE3E: 39          RTS
FE3F: 8B 07       ADDA   #$07
FE41: 39          RTS

put_digit_zero_blank_fe42:
FE42: 81 30       CMPA   #$30
FE44: 26 08       BNE    $FE4E
FE46: 0A EE       DEC    <$EE
FE48: 2B 04       BMI    $FE4E
FE4A: 86 20       LDA    #$20
FE4C: 20 02       BRA    $FE50
FE4E: 0F EE       CLR    <$EE
FE50: A7 C4       STA    ,U
FE52: 33 C5       LEAU   B,U
FE54: 39          RTS

update_hiscore_fe55:
FE55: 8E 10 00    LDX    #$1000
FE58: CE 10 87    LDU    #$1087
FE5B: C6 03       LDB    #$03
FE5D: A6 84       LDA    ,X
FE5F: A1 C4       CMPA   ,U
FE61: 24 01       BCC    $FE64
FE63: 39          RTS
FE64: 26 08       BNE    $FE6E
FE66: 30 01       LEAX   $1,X
FE68: 33 41       LEAU   $1,U
FE6A: 5A          DECB
FE6B: 26 F0       BNE    $FE5D
FE6D: 39          RTS
FE6E: A6 80       LDA    ,X+
FE70: A7 C0       STA    ,U+
FE72: 5A          DECB
FE73: 26 F9       BNE    $FE6E
FE75: 39          RTS

;----------------------------------------------------------------------------
; Blink '1UP' / '2UP' every 16 frames.
;----------------------------------------------------------------------------
blink_player_up_fe76:
FE76: 96 86       LDA    <$86                   ; <$86=player-up blink control
FE78: 2A 01       BPL    $FE7B
FE7A: 39          RTS
FE7B: 96 81       LDA    <$81                   ; <$81=frame counter
FE7D: 84 0F       ANDA   #$0F
FE7F: 27 01       BEQ    $FE82
FE81: 39          RTS
FE82: CE 03 DB    LDU    #$03DB
FE85: 8E 03 C8    LDX    #$03C8
FE88: D6 84       LDB    <$84                   ; <$84=current player (0/1)
FE8A: 27 02       BEQ    $FE8E
FE8C: 1E 13       EXG    X,U
FE8E: 34 54       PSHS   U,X,B
FE90: 8D 0E       BSR    blink_select_fea0
FE92: 35 54       PULS   B,X,U
FE94: 1E 13       EXG    X,U
FE96: C8 01       EORB   #$01
FE98: 0D 82       TST    <$82                   ; <$82=2-player game flag
FE9A: 26 10       BNE    $FEAC
FE9C: C6 02       LDB    #$02
FE9E: 20 0C       BRA    $FEAC

blink_select_fea0:
FEA0: 96 81       LDA    <$81                   ; <$81=frame counter
FEA2: 44          LSRA
FEA3: 44          LSRA
FEA4: 44          LSRA
FEA5: 44          LSRA
FEA6: 94 86       ANDA   <$86                   ; <$86=player-up blink control
FEA8: 27 02       BEQ    $FEAC
FEAA: C6 02       LDB    #$02
FEAC: 86 03       LDA    #$03
FEAE: 3D          MUL
FEAF: 8E FE BD    LDX    #$FEBD
FEB2: 3A          ABX
FEB3: C6 03       LDB    #$03
FEB5: A6 80       LDA    ,X+
FEB7: A7 C2       STA    ,-U
FEB9: 5A          DECB
FEBA: 26 F9       BNE    $FEB5
FEBC: 39          RTS

;----------------------------------------------------------------------------
; Service mode easter egg: a joystick sequence displays a hidden message (bitmap $FF42).
;----------------------------------------------------------------------------
service_easter_egg_fec6:
FEC6: 96 DC       LDA    <$DC
FEC8: 85 10       BITA   #$10
FECA: 26 0E       BNE    $FEDA
FECC: 8E 12 00    LDX    #$1200
FECF: CC 00 00    LDD    #$0000
FED2: ED 81       STD    ,X++
FED4: 8C 12 12    CMPX   #$1212
FED7: 26 F9       BNE    $FED2
FED9: 39          RTS
FEDA: B6 12 01    LDA    $1201
FEDD: 26 39       BNE    $FF18
FEDF: 8E 10 D8    LDX    #$10D8
FEE2: A6 80       LDA    ,X+
FEE4: A1 80       CMPA   ,X+
FEE6: 27 01       BEQ    $FEE9
FEE8: 39          RTS
FEE9: A1 84       CMPA   ,X
FEEB: 26 01       BNE    $FEEE
FEED: 39          RTS
FEEE: A6 80       LDA    ,X+
FEF0: A1 84       CMPA   ,X
FEF2: 27 01       BEQ    $FEF5
FEF4: 39          RTS
FEF5: 96 D8       LDA    <$D8
FEF7: 84 F0       ANDA   #$F0
FEF9: F6 12 00    LDB    $1200
FEFC: 8E 12 02    LDX    #$1202
FEFF: A7 85       STA    B,X
FF01: 7C 12 00    INC    $1200
FF04: 10 8E FF 82 LDY    #$FF82
FF08: EC A1       LDD    ,Y++
FF0A: 10 A3 81    CMPD   ,X++
FF0D: 27 01       BEQ    $FF10
FF0F: 39          RTS
FF10: 8C 12 12    CMPX   #$1212
FF13: 26 F3       BNE    $FF08
FF15: 7C 12 01    INC    $1201
FF18: CE 00 5E    LDU    #$005E
FF1B: 8E FF 42    LDX    #$FF42
FF1E: 86 20       LDA    #$20
FF20: B7 12 00    STA    $1200
FF23: E6 80       LDB    ,X+
FF25: 27 12       BEQ    $FF39
FF27: 4F          CLRA
FF28: 58          ASLB
FF29: 49          ROLA
FF2A: 58          ASLB
FF2B: 49          ROLA
FF2C: 58          ASLB
FF2D: 49          ROLA
FF2E: 58          ASLB
FF2F: 49          ROLA
FF30: 58          ASLB
FF31: 49          ROLA
FF32: 31 CB       LEAY   D,U
FF34: B6 12 00    LDA    $1200
FF37: A7 A4       STA    ,Y
FF39: 7C 12 00    INC    $1200
FF3C: 8C FF 82    CMPX   #$FF82
FF3F: 26 E2       BNE    $FF23
FF41: 39          RTS
