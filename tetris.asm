# ==============================================================================
# TETRIS - COMPLETE MIPS32 RECREATION FOR MARS 4.5
# ==============================================================================
#
# A complete, single-player, retro arcade recreation of classic Tetris.
# Written in standard MIPS32 assembly for MARS 4.5.
#
# BITMAP DISPLAY CONFIGURATION:
# ------------------------------------------------------------------------------
# 1. Tools -> Bitmap Display
# 2. Configure EXACT settings:
#      - Unit Width in Pixels:     4
#      - Unit Height in Pixels:    4
#      - Display Width in Pixels:  512
#      - Display Height in Pixels: 512
#      - Base address for display: 0x10010000 (static data)
# 3. Click "Connect to MIPS"
#
# KEYBOARD SIMULATOR CONFIGURATION:
# ------------------------------------------------------------------------------
# 1. Tools -> Keyboard and Display MMIO Simulator
# 2. Click "Connect to MIPS"
# 3. Type inputs directly into the bottom text area labeled "Keyboard".
#
# CONTROLS:
# ------------------------------------------------------------------------------
#   A / a      : Move left
#   D / d      : Move right
#   S / s      : Soft drop (+1 point per cell)
#   W / w      : Rotate clockwise
#   Z / z      : Rotate counterclockwise
#   SPACE      : Hard drop (+2 points per cell, instant lock)
#   P / p      : Pause / Resume
#   R / r      : Restart game
#   Q / q      : Return to title screen
#
# MEMORY ARCHITECTURE:
# ------------------------------------------------------------------------------
#   0x10010000 .. 0x1001FFFF : 128x128 Logical Framebuffer (65,536 bytes)
#   0x10020000 .. 0x1002FFFF : Game state variables, board, palettes, font data
#   0x7FFFFFFC downward      : Stack Segment ($sp)
#
# ==============================================================================

.data
# ------------------------------------------------------------------------------
# 1. FRAMEBUFFER RESERVATION (65,536 BYTES = 128 x 128 WORDS)
# ------------------------------------------------------------------------------
# Explicitly reserve display memory starting at 0x10010000 so gameplay variables
# are placed safely after 0x1001FFFF.
framebuffer: .space 65536

# ------------------------------------------------------------------------------
# 2. GAME STATE VARIABLES (0x10020000)
# ------------------------------------------------------------------------------
.align 2
game_state:         .word 0       # 0 = TITLE, 1 = PLAYING, 2 = PAUSED, 3 = GAMEOVER
score:              .word 0       # Current score
high_score:         .word 0       # Persistent high score across restarts
lines:              .word 0       # Total cleared lines
level:              .word 1       # Current level (starts at 1)
gravity_interval:   .word 800     # Gravity interval in milliseconds
last_gravity_time:  .word 0       # Millisecond timestamp of last gravity tick
needs_redraw:       .word 1       # 1 if board/piece needs redraw
hud_needs_redraw:   .word 1       # 1 if dynamic HUD needs redraw
frame_counter:      .word 0       # Monotonic frame counter for visual heartbeat

# Active piece state
curr_type:          .word 0       # Piece type (0=I, 1=O, 2=T, 3=S, 4=Z, 5=J, 6=L)
curr_rot:           .word 0       # Current rotation index (0..3)
curr_x:             .word 3       # Current board column (0..9)
curr_y:             .word 0       # Current board row (0..19)
ghost_y:            .word 0       # Landing row for ghost piece

# Next piece & 7-bag randomizer
next_type:          .word 0       # Next piece type (0..6)
bag_index:          .word 7       # Index in current bag (0..7; 7 forces shuffle)
bag:                .byte 0, 1, 2, 3, 4, 5, 6
.align 2
rng_seed:           .word 0x12345678

# 10x20 Playfield Board: 200 bytes (0 = empty, 1..7 = locked piece type + 1)
board:              .space 200

# Scratch buffer for integer-to-string formatting (null-terminated)
num_buf:            .space 32

# ------------------------------------------------------------------------------
# 3. COLOR PALETTES (0x00RRGGBB)
# ------------------------------------------------------------------------------
.align 2
# Base colors: I:Cyan, O:Yellow, T:Purple, S:Green, Z:Red, J:Blue, L:Orange
piece_color_base:
    .word 0x0000D0D0    # I: Cyan
    .word 0x00D8C800    # O: Yellow
    .word 0x009000D0    # T: Purple
    .word 0x0000C810    # S: Green
    .word 0x00D01010    # Z: Red
    .word 0x001830D0    # J: Blue
    .word 0x00D06800    # L: Orange

# Highlight colors (top and left bevels)
piece_color_hi:
    .word 0x0080FFFF    # I Highlight
    .word 0x00FFFF80    # O Highlight
    .word 0x00D060FF    # T Highlight
    .word 0x0060FF60    # S Highlight
    .word 0x00FF6060    # Z Highlight
    .word 0x007090FF    # J Highlight
    .word 0x00FFA840    # L Highlight

# Shadow colors (bottom and right bevels)
piece_color_sh:
    .word 0x00006060    # I Shadow
    .word 0x00686000    # O Shadow
    .word 0x00400060    # T Shadow
    .word 0x00006008    # S Shadow
    .word 0x00600808    # Z Shadow
    .word 0x00081860    # J Shadow
    .word 0x00603000    # L Shadow

# Ghost piece colors (dark wireframe shade)
piece_color_ghost:
    .word 0x00004848    # I Ghost
    .word 0x00484400    # O Ghost
    .word 0x00340048    # T Ghost
    .word 0x00004806    # S Ghost
    .word 0x00480606    # Z Ghost
    .word 0x00061048    # J Ghost
    .word 0x00482400    # L Ghost

# UI Theme Constants
.eqv COLOR_BG            0x000F1018
.eqv COLOR_BOARD_BG      0x00050508
.eqv COLOR_BORDER        0x00607080
.eqv COLOR_BORDER_HI     0x00A0B0C0
.eqv COLOR_TEXT_WHITE    0x00FFFFFF
.eqv COLOR_TEXT_YELLOW   0x00FFD700
.eqv COLOR_TEXT_CYAN     0x0000FFFF
.eqv COLOR_TEXT_GRAY     0x00788898
.eqv COLOR_OVERLAY_BG    0x000A0A14
.eqv COLOR_OVERLAY_RED   0x00200808

# Game States
.eqv STATE_TITLE         0
.eqv STATE_PLAYING       1
.eqv STATE_PAUSED        2
.eqv STATE_GAMEOVER      3

# Cell Drawing Modes
.eqv MODE_EMPTY          0
.eqv MODE_LOCKED         1
.eqv MODE_GHOST          2
.eqv MODE_ACTIVE         3

# Playfield Layout Constants
.eqv PLAYFIELD_X         10
.eqv PLAYFIELD_Y         14
.eqv PLAYFIELD_W         50
.eqv PLAYFIELD_H         100

# ------------------------------------------------------------------------------
# 4. TETROMINO ROTATION OFFSET TABLE
# ------------------------------------------------------------------------------
# 7 pieces * 4 rotations * 4 blocks * 2 bytes (X, Y) = 224 bytes
.align 2
piece_offsets:
    # Piece 0: I (Cyan)
    .byte 0, 0, 1, 0, 2, 0, 3, 0  # Rot 0 (horizontal)
    .byte 2, 0, 2, 1, 2, 2, 2, 3  # Rot 1 (vertical)
    .byte 0, 1, 1, 1, 2, 1, 3, 1  # Rot 2 (horizontal)
    .byte 1, 0, 1, 1, 1, 2, 1, 3  # Rot 3 (vertical)
    # Piece 1: O (Yellow)
    .byte 1, 0, 2, 0, 1, 1, 2, 1  # Rot 0
    .byte 1, 0, 2, 0, 1, 1, 2, 1  # Rot 1
    .byte 1, 0, 2, 0, 1, 1, 2, 1  # Rot 2
    .byte 1, 0, 2, 0, 1, 1, 2, 1  # Rot 3
    # Piece 2: T (Purple)
    .byte 1, 0, 0, 1, 1, 1, 2, 1  # Rot 0 (point up)
    .byte 1, 0, 1, 1, 2, 1, 1, 2  # Rot 1 (point right)
    .byte 0, 1, 1, 1, 2, 1, 1, 2  # Rot 2 (point down)
    .byte 1, 0, 0, 1, 1, 1, 1, 2  # Rot 3 (point left)
    # Piece 3: S (Green)
    .byte 1, 0, 2, 0, 0, 1, 1, 1  # Rot 0
    .byte 1, 0, 1, 1, 2, 1, 2, 2  # Rot 1
    .byte 1, 1, 2, 1, 0, 2, 1, 2  # Rot 2
    .byte 0, 0, 0, 1, 1, 1, 1, 2  # Rot 3
    # Piece 4: Z (Red)
    .byte 0, 0, 1, 0, 1, 1, 2, 1  # Rot 0
    .byte 2, 0, 1, 1, 2, 1, 1, 2  # Rot 1
    .byte 0, 1, 1, 1, 1, 2, 2, 2  # Rot 2
    .byte 1, 0, 0, 1, 1, 1, 0, 2  # Rot 3
    # Piece 5: J (Blue)
    .byte 0, 0, 0, 1, 1, 1, 2, 1  # Rot 0
    .byte 1, 0, 2, 0, 1, 1, 1, 2  # Rot 1
    .byte 0, 1, 1, 1, 2, 1, 2, 2  # Rot 2
    .byte 1, 0, 1, 1, 0, 2, 1, 2  # Rot 3
    # Piece 6: L (Orange)
    .byte 2, 0, 0, 1, 1, 1, 2, 1  # Rot 0
    .byte 1, 0, 1, 1, 1, 2, 2, 2  # Rot 1
    .byte 0, 1, 1, 1, 2, 1, 0, 2  # Rot 2
    .byte 0, 0, 1, 0, 1, 1, 1, 2  # Rot 3

# ------------------------------------------------------------------------------
# 5. UI STRINGS
# ------------------------------------------------------------------------------
.align 2
str_title:          .asciiz "TETRIS"
str_score:          .asciiz "SCORE"
str_high:           .asciiz "HIGH"
str_level:          .asciiz "LEVEL"
str_lines:          .asciiz "LINES"
str_next:           .asciiz "NEXT"
str_ctrl_head:      .asciiz "CONTROLS"
str_ctrl_move:      .asciiz "A/D MOVE"
str_ctrl_rot:       .asciiz "W/Z ROT"
str_ctrl_drop:      .asciiz "S/SPC DRP"
str_ctrl_pause:     .asciiz "P:PAUSE"
str_ctrl_rst:       .asciiz "R:RESET"

str_paused_title:   .asciiz "PAUSED"
str_paused_sub:     .asciiz "PRESS P"

str_gameover_head:  .asciiz "GAME OVER"
str_final_score:    .asciiz "SCORE:"
str_restart_sub:    .asciiz "PRESS R"

str_splash_title:   .asciiz "TETRIS"
str_splash_sub:     .asciiz "MIPS EDITION"
str_splash_play:    .asciiz "PRESS SPACE"
str_splash_info1:   .asciiz "MARS 4.5"
str_splash_info2:   .asciiz "RETRO ARCADE"

# ------------------------------------------------------------------------------
# 6. COMPACT 3x5 BITMAP FONT TABLE (ASCII 32 to 90, 59 chars * 5 bytes = 295 bytes)
# ------------------------------------------------------------------------------
.align 2
font_data:
    .byte 0x00, 0x00, 0x00, 0x00, 0x00  # 32: SPACE
    .byte 0x02, 0x02, 0x02, 0x00, 0x02  # 33: !
    .byte 0x05, 0x05, 0x00, 0x00, 0x00  # 34: "
    .byte 0x00, 0x00, 0x00, 0x00, 0x00  # 35: #
    .byte 0x00, 0x00, 0x00, 0x00, 0x00  # 36: $
    .byte 0x00, 0x00, 0x00, 0x00, 0x00  # 37: %
    .byte 0x00, 0x00, 0x00, 0x00, 0x00  # 38: &
    .byte 0x02, 0x02, 0x00, 0x00, 0x00  # 39: '
    .byte 0x02, 0x04, 0x04, 0x04, 0x02  # 40: (
    .byte 0x02, 0x01, 0x01, 0x01, 0x02  # 41: )
    .byte 0x00, 0x05, 0x02, 0x05, 0x00  # 42: *
    .byte 0x00, 0x02, 0x07, 0x02, 0x00  # 43: +
    .byte 0x00, 0x00, 0x00, 0x02, 0x04  # 44: ,
    .byte 0x00, 0x00, 0x07, 0x00, 0x00  # 45: -
    .byte 0x00, 0x00, 0x00, 0x00, 0x02  # 46: .
    .byte 0x01, 0x01, 0x02, 0x04, 0x04  # 47: /
    .byte 0x07, 0x05, 0x05, 0x05, 0x07  # 48: 0
    .byte 0x02, 0x06, 0x02, 0x02, 0x07  # 49: 1
    .byte 0x07, 0x01, 0x07, 0x04, 0x07  # 50: 2
    .byte 0x07, 0x01, 0x07, 0x01, 0x07  # 51: 3
    .byte 0x05, 0x05, 0x07, 0x01, 0x01  # 52: 4
    .byte 0x07, 0x04, 0x07, 0x01, 0x07  # 53: 5
    .byte 0x07, 0x04, 0x07, 0x05, 0x07  # 54: 6
    .byte 0x07, 0x01, 0x02, 0x02, 0x02  # 55: 7
    .byte 0x07, 0x05, 0x07, 0x05, 0x07  # 56: 8
    .byte 0x07, 0x05, 0x07, 0x01, 0x07  # 57: 9
    .byte 0x00, 0x02, 0x00, 0x02, 0x00  # 58: :
    .byte 0x00, 0x02, 0x00, 0x02, 0x04  # 59: ;
    .byte 0x01, 0x02, 0x04, 0x02, 0x01  # 60: <
    .byte 0x00, 0x07, 0x00, 0x07, 0x00  # 61: =
    .byte 0x04, 0x02, 0x01, 0x02, 0x04  # 62: >
    .byte 0x07, 0x01, 0x03, 0x00, 0x02  # 63: ?
    .byte 0x07, 0x05, 0x07, 0x04, 0x07  # 64: @
    .byte 0x07, 0x05, 0x07, 0x05, 0x05  # 65: A
    .byte 0x06, 0x05, 0x06, 0x05, 0x06  # 66: B
    .byte 0x07, 0x04, 0x04, 0x04, 0x07  # 67: C
    .byte 0x06, 0x05, 0x05, 0x05, 0x06  # 68: D
    .byte 0x07, 0x04, 0x07, 0x04, 0x07  # 69: E
    .byte 0x07, 0x04, 0x07, 0x04, 0x04  # 70: F
    .byte 0x07, 0x04, 0x05, 0x05, 0x07  # 71: G
    .byte 0x05, 0x05, 0x07, 0x05, 0x05  # 72: H
    .byte 0x07, 0x02, 0x02, 0x02, 0x07  # 73: I
    .byte 0x01, 0x01, 0x01, 0x05, 0x02  # 74: J
    .byte 0x05, 0x05, 0x06, 0x05, 0x05  # 75: K
    .byte 0x04, 0x04, 0x04, 0x04, 0x07  # 76: L
    .byte 0x05, 0x07, 0x05, 0x05, 0x05  # 77: M
    .byte 0x06, 0x05, 0x05, 0x05, 0x05  # 78: N
    .byte 0x07, 0x05, 0x05, 0x05, 0x07  # 79: O
    .byte 0x07, 0x05, 0x07, 0x04, 0x04  # 80: P
    .byte 0x07, 0x05, 0x05, 0x07, 0x01  # 81: Q
    .byte 0x07, 0x05, 0x06, 0x05, 0x05  # 82: R
    .byte 0x07, 0x04, 0x07, 0x01, 0x07  # 83: S
    .byte 0x07, 0x02, 0x02, 0x02, 0x02  # 84: T
    .byte 0x05, 0x05, 0x05, 0x05, 0x07  # 85: U
    .byte 0x05, 0x05, 0x05, 0x05, 0x02  # 86: V
    .byte 0x05, 0x05, 0x05, 0x07, 0x05  # 87: W
    .byte 0x05, 0x05, 0x02, 0x05, 0x05  # 88: X
    .byte 0x05, 0x05, 0x02, 0x02, 0x02  # 89: Y
    .byte 0x07, 0x01, 0x02, 0x04, 0x07  # 90: Z

# ==============================================================================
# CODE SEGMENT
# ==============================================================================
.text
.globl main

# ------------------------------------------------------------------------------
# PROGRAM ENTRY POINT
# ------------------------------------------------------------------------------
main:
    # Initialize Random Number Generator seed with system time
    li $v0, 30
    syscall
    sw $a0, rng_seed

    # Initialize high score to 0
    sw $zero, high_score

    # Show Title / Splash screen
    jal show_title_screen

# ------------------------------------------------------------------------------
# MAIN GAME LOOP
# ------------------------------------------------------------------------------
game_loop:
    # 1. Poll keyboard input (bounded to 1 key event per frame)
    jal poll_keyboard
    beqz $v0, gl_no_input
    move $a0, $v0
    jal handle_input

gl_no_input:
    # 2. Get fresh system timestamp in milliseconds immediately before gravity
    li $v0, 30
    syscall                # $a0 = current timestamp (ms)

    # 3. If playing, apply gravity based on elapsed time
    jal update_gravity

    # 4. Render active frame if changes occurred
    jal render_frame

    # 5. Sleep 16 ms: yields CPU to host OS and Swing GUI (~60 FPS)
    li $v0, 32
    li $a0, 16
    syscall

    # Repeat main loop
    j game_loop

# ------------------------------------------------------------------------------
# TITLE SCREEN ROUTINE
# ------------------------------------------------------------------------------
show_title_screen:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    li $t0, STATE_TITLE
    sw $t0, game_state

    # Clear screen with background color
    li $a0, 0
    li $a1, 0
    li $a2, 128
    li $a3, 128
    li $t0, COLOR_BG
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    # Outer decorative border
    li $a0, 4
    li $a1, 4
    li $a2, 120
    li $a3, 120
    li $t0, COLOR_BORDER
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_border
    addi $sp, $sp, 4

    li $a0, 6
    li $a1, 6
    li $a2, 116
    li $a3, 116
    li $t0, COLOR_BORDER_HI
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_border
    addi $sp, $sp, 4

    # Title Banner Box: (20, 20, 88, 30)
    li $a0, 20
    li $a1, 20
    li $a2, 88
    li $a3, 30
    li $t0, COLOR_BOARD_BG
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    li $a0, 20
    li $a1, 20
    li $a2, 88
    li $a3, 30
    li $t0, COLOR_TEXT_YELLOW
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_border
    addi $sp, $sp, 4

    # Title text: "TETRIS"
    li $a0, 52
    li $a1, 26
    la $a2, str_splash_title
    li $a3, COLOR_TEXT_YELLOW
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    # Subtitle: "MIPS EDITION"
    li $a0, 40
    li $a1, 38
    la $a2, str_splash_sub
    li $a3, COLOR_TEXT_CYAN
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    # High score banner
    li $a0, 36
    li $a1, 58
    la $a2, str_high
    li $a3, COLOR_TEXT_WHITE
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    li $a0, 58
    li $a1, 58
    lw $a2, high_score
    li $a3, 6
    li $t0, COLOR_TEXT_CYAN
    li $t1, COLOR_BG
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal draw_number
    addi $sp, $sp, 8

    # Start Prompt Box: (24, 72, 80, 16)
    li $a0, 24
    li $a1, 72
    li $a2, 80
    li $a3, 16
    li $t0, COLOR_BOARD_BG
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    li $a0, 24
    li $a1, 72
    li $a2, 80
    li $a3, 16
    li $t0, COLOR_BORDER
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_border
    addi $sp, $sp, 4

    # "PRESS SPACE"
    li $a0, 42
    li $a1, 78
    la $a2, str_splash_play
    li $a3, COLOR_TEXT_WHITE
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    # Bottom Controls Help
    li $a0, 28
    li $a1, 98
    la $a2, str_ctrl_move
    li $a3, COLOR_TEXT_GRAY
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    li $a0, 68
    li $a1, 98
    la $a2, str_ctrl_rot
    li $a3, COLOR_TEXT_GRAY
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    li $a0, 24
    li $a1, 106
    la $a2, str_ctrl_drop
    li $a3, COLOR_TEXT_GRAY
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    li $a0, 68
    li $a1, 106
    la $a2, str_ctrl_pause
    li $a3, COLOR_TEXT_GRAY
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# INITIALIZE / RESTART GAME
# ------------------------------------------------------------------------------
restart_game:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Reset board cells to 0
    la $t0, board
    li $t1, 0
rg_clear_board:
    bge $t1, 200, rg_board_cleared
    sb $zero, 0($t0)
    addi $t0, $t0, 1
    addi $t1, $t1, 1
    j rg_clear_board

rg_board_cleared:
    # Reset game stats
    sw $zero, score
    sw $zero, lines
    li $t0, 1
    sw $t0, level
    li $t0, 800
    sw $t0, gravity_interval

    # Reset 7-bag randomizer
    li $t0, 7
    sw $t0, bag_index

    # Initialize piece queue
    jal get_next_bag_piece
    sw $v0, curr_type
    jal get_next_bag_piece
    sw $v0, next_type

    # Reset active piece position
    li $t0, 3
    sw $t0, curr_x
    sw $zero, curr_y
    sw $zero, curr_rot

    # Set state to PLAYING
    li $t0, STATE_PLAYING
    sw $t0, game_state

    # Sync gravity timer
    li $v0, 30
    syscall
    sw $a0, last_gravity_time

    # Redraw HUD, board, and queue
    jal draw_hud
    li $t0, 1
    sw $t0, needs_redraw
    sw $t0, hud_needs_redraw

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# KEYBOARD INPUT HANDLERS
# ------------------------------------------------------------------------------
# poll_keyboard: checks MMIO Receiver Control (0xFFFF0000).
# Returns ASCII char in $v0, or 0 if no event.
poll_keyboard:
    lui $t0, 0xFFFF
    lw $t1, 0($t0)         # Receiver Control
    andi $t1, $t1, 1
    beqz $t1, pk_empty
    lw $v0, 4($t0)         # Receiver Data
    sw $zero, 0($t0)       # Explicitly clear Receiver Control ready bit
    # Convert lowercase 'a'..'z' to uppercase 'A'..'Z'
    blt $v0, 'a', pk_done
    bgt $v0, 'z', pk_done
    addi $v0, $v0, -32
pk_done:
    jr $ra
pk_empty:
    li $v0, 0
    jr $ra

# handle_input: processes key code in $a0
handle_input:
    addi $sp, $sp, -8
    sw $ra, 4($sp)
    sw $s0, 0($sp)
    move $s0, $a0          # s0 = key code

    # Global key: 'R' always restarts
    beq $s0, 'R', hi_do_restart

    # Global key: 'Q' returns to title
    beq $s0, 'Q', hi_do_title

    # State-based handling
    lw $t0, game_state
    beq $t0, STATE_TITLE, hi_title
    beq $t0, STATE_PAUSED, hi_paused
    beq $t0, STATE_GAMEOVER, hi_gameover
    beq $t0, STATE_PLAYING, hi_playing
    j hi_exit

hi_do_restart:
    jal restart_game
    j hi_exit

hi_do_title:
    jal show_title_screen
    j hi_exit

hi_title:
    # Any of SPACE, ENTER(10), or 'W' starts the game
    beq $s0, ' ', hi_start_play
    beq $s0, 10, hi_start_play
    beq $s0, 'W', hi_start_play
    j hi_exit
hi_start_play:
    jal restart_game
    j hi_exit

hi_gameover:
    # Only R and Q handled (already checked above)
    j hi_exit

hi_paused:
    # 'P' toggles pause off
    beq $s0, 'P', hi_unpause
    j hi_exit
hi_unpause:
    li $t0, STATE_PLAYING
    sw $t0, game_state
    # Sync gravity timer so piece does not immediately drop
    li $v0, 30
    syscall
    sw $a0, last_gravity_time
    li $t1, 1
    sw $t1, needs_redraw
    j hi_exit

hi_playing:
    beq $s0, 'A', hi_left
    beq $s0, 'D', hi_right
    beq $s0, 'S', hi_soft_drop
    beq $s0, 'W', hi_rot_cw
    beq $s0, 'Z', hi_rot_ccw
    beq $s0, ' ', hi_hard_drop
    beq $s0, 'P', hi_pause
    j hi_exit

hi_left:
    li $a0, -1
    li $a1, 0
    jal move_piece
    j hi_exit

hi_right:
    li $a0, 1
    li $a1, 0
    jal move_piece
    j hi_exit

hi_soft_drop:
    jal soft_drop
    j hi_exit

hi_rot_cw:
    li $a0, 1              # +1: clockwise
    jal rotate_piece
    j hi_exit

hi_rot_ccw:
    li $a0, -1             # -1: counterclockwise
    jal rotate_piece
    j hi_exit

hi_hard_drop:
    jal hard_drop
    j hi_exit

hi_pause:
    li $t0, STATE_PAUSED
    sw $t0, game_state
    jal draw_pause_screen
    j hi_exit

hi_exit:
    lw $s0, 0($sp)
    lw $ra, 4($sp)
    addi $sp, $sp, 8
    jr $ra

# ------------------------------------------------------------------------------
# GRAVITY & TIMING
# ------------------------------------------------------------------------------
# update_gravity(a0 = current_time_ms)
update_gravity:
    addi $sp, $sp, -8
    sw $ra, 4($sp)
    sw $s0, 0($sp)
    move $s0, $a0          # s0 = current time

    lw $t0, game_state
    bne $t0, STATE_PLAYING, ug_exit

    lw $t1, last_gravity_time
    subu $t2, $s0, $t1     # elapsed = current_time - last_gravity_time
    # Clock safety guard: if elapsed is negative (clock sync/backward jump), reset
    bltz $t2, ug_reset_timer
    lw $t3, gravity_interval
    blt $t2, $t3, ug_exit
    j ug_do_tick

ug_reset_timer:
    sw $s0, last_gravity_time
    j ug_exit

ug_do_tick:

    # Interval elapsed -> tick gravity
    sw $s0, last_gravity_time

    # Try moving down 1 cell
    li $a0, 0
    li $a1, 1
    jal move_piece
    bnez $v0, ug_exit      # moved successfully -> done

    # Cannot move down -> lock piece into board!
    jal lock_piece

ug_exit:
    lw $s0, 0($sp)
    lw $ra, 4($sp)
    addi $sp, $sp, 8
    jr $ra

# ------------------------------------------------------------------------------
# TETROMINO MOVEMENT & COLLISION
# ------------------------------------------------------------------------------
# validate_position(a0 = type, a1 = rot, a2 = test_x, a3 = test_y)
# Returns $v0 = 1 if valid, 0 if collision.
validate_position:
    # Compute offset table pointer: piece_offsets + (type * 32) + (rot * 8)
    sll $t0, $a0, 5        # type * 32
    sll $t1, $a1, 3        # rot * 8
    addu $t0, $t0, $t1
    la $t2, piece_offsets
    addu $t2, $t2, $t0     # t2 = &offsets[type][rot][0]

    la $t3, board
    li $t4, 0              # block index i = 0..3

vp_loop:
    bge $t4, 4, vp_valid
    lb $t5, 0($t2)         # dx
    lb $t6, 1($t2)         # dy
    addi $t2, $t2, 2
    addi $t4, $t4, 1

    addu $t7, $a2, $t5     # bx = test_x + dx
    addu $t8, $a3, $t6     # by = test_y + dy

    # Horizontal wall bounds check (0 <= bx < 10)
    bltz $t7, vp_invalid
    bge $t7, 10, vp_invalid

    # Floor bounds check (by < 20)
    bge $t8, 20, vp_invalid

    # Ceiling check: by < 0 is allowed (spawning area above board)
    bltz $t8, vp_loop

    # Board collision check: board[by * 10 + bx] == 0
    mul $t9, $t8, 10
    addu $t9, $t9, $t7
    addu $t9, $t3, $t9     # &board[by][bx]
    lb $t9, 0($t9)
    bnez $t9, vp_invalid

    j vp_loop

vp_valid:
    li $v0, 1
    jr $ra

vp_invalid:
    li $v0, 0
    jr $ra

# move_piece(a0 = dx, a1 = dy) -> v0 = 1 if moved, 0 if blocked
move_piece:
    addi $sp, $sp, -12
    sw $ra, 8($sp)
    sw $s0, 4($sp)
    sw $s1, 0($sp)

    lw $t0, curr_x
    addu $s0, $t0, $a0     # s0 = test_x = curr_x + dx
    lw $t1, curr_y
    addu $s1, $t1, $a1     # s1 = test_y = curr_y + dy

    lw $a0, curr_type
    lw $a1, curr_rot
    move $a2, $s0
    move $a3, $s1
    jal validate_position

    beqz $v0, mp_fail

    # Position is valid: apply movement
    sw $s0, curr_x
    sw $s1, curr_y
    li $t0, 1
    sw $t0, needs_redraw
    li $v0, 1
    j mp_exit

mp_fail:
    li $v0, 0

mp_exit:
    lw $s1, 0($sp)
    lw $s0, 4($sp)
    lw $ra, 8($sp)
    addi $sp, $sp, 12
    jr $ra

# rotate_piece(a0 = direction: +1 for CW, -1 for CCW)
rotate_piece:
    addi $sp, $sp, -16
    sw $ra, 12($sp)
    sw $s0, 8($sp)
    sw $s1, 4($sp)
    sw $s2, 0($sp)

    # Compute new_rot = (curr_rot + direction) & 3
    lw $t0, curr_rot
    addu $t0, $t0, $a0
    andi $s0, $t0, 3       # s0 = new_rot

    lw $s1, curr_x         # s1 = curr_x
    lw $s2, curr_y         # s2 = curr_y

    # Test 1: In-place rotation (dx = 0)
    lw $a0, curr_type
    move $a1, $s0
    move $a2, $s1
    move $a3, $s2
    jal validate_position
    bnez $v0, rot_success

    # Test 2: Wall kick right (+1)
    lw $a0, curr_type
    move $a1, $s0
    addi $a2, $s1, 1
    move $a3, $s2
    jal validate_position
    beqz $v0, rot_try_left
    addi $s1, $s1, 1
    j rot_success

rot_try_left:
    # Test 3: Wall kick left (-1)
    lw $a0, curr_type
    move $a1, $s0
    addi $a2, $s1, -1
    move $a3, $s2
    jal validate_position
    beqz $v0, rot_try_i_kicks
    addi $s1, $s1, -1
    j rot_success

rot_try_i_kicks:
    # Tests 4 & 5: Double kicks for I piece (curr_type == 0)
    lw $t0, curr_type
    bnez $t0, rot_failed

    # Kick right +2
    lw $a0, curr_type
    move $a1, $s0
    addi $a2, $s1, 2
    move $a3, $s2
    jal validate_position
    beqz $v0, rot_try_i_left2
    addi $s1, $s1, 2
    j rot_success

rot_try_i_left2:
    # Kick left -2
    lw $a0, curr_type
    move $a1, $s0
    addi $a2, $s1, -2
    move $a3, $s2
    jal validate_position
    beqz $v0, rot_failed
    addi $s1, $s1, -2
    j rot_success

rot_success:
    sw $s0, curr_rot
    sw $s1, curr_x
    li $t0, 1
    sw $t0, needs_redraw
    li $v0, 1
    j rot_exit

rot_failed:
    li $v0, 0

rot_exit:
    lw $s2, 0($sp)
    lw $s1, 4($sp)
    lw $s0, 8($sp)
    lw $ra, 12($sp)
    addi $sp, $sp, 16
    jr $ra

# soft_drop: moves piece down 1 cell, awards +1 point
soft_drop:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    li $a0, 0
    li $a1, 1
    jal move_piece
    beqz $v0, sd_done

    # Add 1 point for soft drop
    lw $t0, score
    addi $t0, $t0, 1
    sw $t0, score

    # Check high score
    lw $t1, high_score
    ble $t0, $t1, sd_sync_time
    sw $t0, high_score

sd_sync_time:
    li $t2, 1
    sw $t2, hud_needs_redraw
    # Reset gravity timer to prevent double step
    li $v0, 30
    syscall
    sw $a0, last_gravity_time

sd_done:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# calculate_ghost_y: predicts landing row for active piece
# Updates ghost_y in memory and returns row in $v0
calculate_ghost_y:
    addi $sp, $sp, -8
    sw $ra, 4($sp)
    sw $s0, 0($sp)

    lw $s0, curr_y         # gy = curr_y
cgy_find_y:
    bge $s0, 20, cgy_found # Safety clamp to board height
    lw $a0, curr_type
    lw $a1, curr_rot
    lw $a2, curr_x
    addi $a3, $s0, 1       # test gy + 1
    jal validate_position
    beqz $v0, cgy_found
    addi $s0, $s0, 1
    j cgy_find_y

cgy_found:
    sw $s0, ghost_y
    move $v0, $s0
    lw $s0, 0($sp)
    lw $ra, 4($sp)
    addi $sp, $sp, 8
    jr $ra

# hard_drop: instantly drops piece to ghost landing position and locks
hard_drop:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Recompute ghost_y to guarantee freshness for current position
    jal calculate_ghost_y

    # Compute drop distance: ghost_y - curr_y
    lw $t0, curr_y
    lw $t1, ghost_y
    subu $t2, $t1, $t0     # drop distance
    sw $t1, curr_y         # instantly move to landing row

    # Award +2 points per dropped cell
    sll $t3, $t2, 1        # drop_dist * 2
    lw $t4, score
    addu $t4, $t4, $t3
    sw $t4, score

    # Check high score
    lw $t5, high_score
    ble $t4, $t5, hd_lock
    sw $t4, high_score

hd_lock:
    li $t6, 1
    sw $t6, hud_needs_redraw
    jal lock_piece

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# lock_piece: writes active piece blocks into board array
lock_piece:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Offsets pointer
    lw $t0, curr_type
    lw $t1, curr_rot
    sll $t0, $t0, 5
    sll $t1, $t1, 3
    addu $t0, $t0, $t1
    la $t2, piece_offsets
    addu $t2, $t2, $t0

    la $t3, board
    lw $t4, curr_x
    lw $t5, curr_y
    lw $t6, curr_type
    addi $t6, $t6, 1       # stored cell value = type + 1 (1..7)

    li $t7, 0              # i = 0..3
lp_loop:
    bge $t7, 4, lp_done
    lb $t8, 0($t2)         # dx
    lb $t9, 1($t2)         # dy
    addi $t2, $t2, 2
    addi $t7, $t7, 1

    addu $t8, $t4, $t8     # bx = curr_x + dx
    addu $t9, $t5, $t9     # by = curr_y + dy

    bltz $t9, lp_loop      # ignore cells above board
    bge $t9, 20, lp_loop
    bltz $t8, lp_loop
    bge $t8, 10, lp_loop

    mul $t0, $t9, 10
    addu $t0, $t0, $t8
    addu $t0, $t3, $t0
    sb $t6, 0($t0)         # board[by][bx] = type + 1
    j lp_loop

lp_done:
    # Check and clear completed rows
    jal check_and_clear_rows

    # Spawn next tetromino
    jal spawn_piece

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# BOARD MANAGEMENT & LINE CLEARING
# ------------------------------------------------------------------------------
check_and_clear_rows:
    addi $sp, $sp, -28
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)
    sw $s5, 0($sp)

    # s0 = read_y (19 down to 0)
    # s1 = write_y (19 down to 0)
    # s2 = lines_cleared count
    li $s0, 19
    li $s1, 19
    li $s2, 0
    la $s3, board

ccr_row_loop:
    bltz $s0, ccr_clear_top_rows

    # Check if row s0 is full
    mul $t0, $s0, 10
    addu $t0, $s3, $t0     # &board[s0][0]
    li $t1, 0              # x = 0
    li $t2, 1              # is_full = 1

ccr_check_x:
    bge $t1, 10, ccr_row_checked
    lb $t3, 0($t0)
    beqz $t3, ccr_not_full
    addi $t0, $t0, 1
    addi $t1, $t1, 1
    j ccr_check_x

ccr_not_full:
    li $t2, 0

ccr_row_checked:
    beqz $t2, ccr_keep_row

    # Full row detected!
    addi $s2, $s2, 1
    addi $s0, $s0, -1
    j ccr_row_loop

ccr_keep_row:
    beq $s1, $s0, ccr_no_copy
    mul $t0, $s0, 10
    addu $t0, $s3, $t0     # src = &board[read_y][0]
    mul $t1, $s1, 10
    addu $t1, $s3, $t1     # dst = &board[write_y][0]
    li $t4, 0
ccr_copy_loop:
    bge $t4, 10, ccr_no_copy
    lb $t5, 0($t0)
    sb $t5, 0($t1)
    addi $t0, $t0, 1
    addi $t1, $t1, 1
    addi $t4, $t4, 1
    j ccr_copy_loop

ccr_no_copy:
    addi $s1, $s1, -1
    addi $s0, $s0, -1
    j ccr_row_loop

ccr_clear_top_rows:
    bltz $s1, ccr_update_stats
    mul $t1, $s1, 10
    addu $t1, $s3, $t1     # dst = &board[write_y][0]
    li $t4, 0
ccr_zero_loop:
    bge $t4, 10, ccr_zero_next
    sb $zero, 0($t1)
    addi $t1, $t1, 1
    addi $t4, $t4, 1
    j ccr_zero_loop
ccr_zero_next:
    addi $s1, $s1, -1
    j ccr_clear_top_rows

ccr_update_stats:
    beqz $s2, ccr_exit

    # lines += lines_cleared
    lw $t0, lines
    addu $t0, $t0, $s2
    sw $t0, lines

    # Calculate line clear score:
    # 1 line:  100 * level
    # 2 lines: 300 * level
    # 3 lines: 500 * level
    # 4 lines: 800 * level
    li $t1, 100
    beq $s2, 1, ccr_calc_pts
    li $t1, 300
    beq $s2, 2, ccr_calc_pts
    li $t1, 500
    beq $s2, 3, ccr_calc_pts
    li $t1, 800

ccr_calc_pts:
    lw $t2, level
    mul $t1, $t1, $t2
    lw $t3, score
    addu $t3, $t3, $t1
    sw $t3, score

    # Check high score
    lw $t4, high_score
    ble $t3, $t4, ccr_check_level
    sw $t3, high_score

ccr_check_level:
    # level = 1 + (lines / 10)
    lw $t0, lines
    li $t5, 10
    divu $t0, $t5
    mflo $t6
    addi $t6, $t6, 1
    sw $t6, level

    # gravity_interval = max(120, 850 - level * 70)
    li $t7, 70
    mul $t7, $t6, $t7
    li $t8, 850
    subu $t8, $t8, $t7
    bge $t8, 120, ccr_store_grav
    li $t8, 120
ccr_store_grav:
    sw $t8, gravity_interval

    li $t9, 1
    sw $t9, hud_needs_redraw
    sw $t9, needs_redraw

ccr_exit:
    lw $s5, 0($sp)
    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addi $sp, $sp, 28
    jr $ra

# spawn_piece: brings in next tetromino and checks game over
spawn_piece:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $t0, next_type
    sw $t0, curr_type
    jal get_next_bag_piece
    sw $v0, next_type

    li $t0, 3
    sw $t0, curr_x
    sw $zero, curr_y
    sw $zero, curr_rot

    # Synchronize gravity timer
    li $v0, 30
    syscall
    sw $a0, last_gravity_time

    # Collision test at spawn position
    lw $a0, curr_type
    lw $a1, curr_rot
    lw $a2, curr_x
    lw $a3, curr_y
    jal validate_position
    bnez $v0, sp_success

    # Spawn blocked -> GAME OVER!
    li $t0, STATE_GAMEOVER
    sw $t0, game_state
    jal draw_game_over_screen
    j sp_exit

sp_success:
    li $t0, 1
    sw $t0, needs_redraw
    sw $t0, hud_needs_redraw

sp_exit:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# 7-BAG RANDOMIZER
# ------------------------------------------------------------------------------
# get_next_bag_piece -> returns piece type in $v0 (0..6)
get_next_bag_piece:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $t0, bag_index
    blt $t0, 7, gnb_fetch
    jal shuffle_bag

gnb_fetch:
    lw $t0, bag_index
    la $t1, bag
    addu $t1, $t1, $t0
    lb $v0, 0($t1)
    addi $t0, $t0, 1
    sw $t0, bag_index

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# shuffle_bag: Fisher-Yates shuffle of bag [0..6]
shuffle_bag:
    addi $sp, $sp, -12
    sw $ra, 8($sp)
    sw $s0, 4($sp)
    sw $s1, 0($sp)

    # Reset bag to [0, 1, 2, 3, 4, 5, 6]
    la $t0, bag
    li $t1, 0
sb_reset:
    bge $t1, 7, sb_shuffle
    sb $t1, 0($t0)
    addi $t0, $t0, 1
    addi $t1, $t1, 1
    j sb_reset

sb_shuffle:
    li $s0, 6              # i = 6 down to 1
sb_loop:
    blez $s0, sb_done
    addi $a0, $s0, 1       # rand_int(i + 1)
    jal rand_int
    move $s1, $v0          # s1 = r in [0, i]

    # Swap bag[i] and bag[r]
    la $t0, bag
    addu $t1, $t0, $s0     # &bag[i]
    addu $t2, $t0, $s1     # &bag[r]
    lb $t3, 0($t1)
    lb $t4, 0($t2)
    sb $t4, 0($t1)
    sb $t3, 0($t2)

    addi $s0, $s0, -1
    j sb_loop

sb_done:
    sw $zero, bag_index
    lw $s1, 0($sp)
    lw $s0, 4($sp)
    lw $ra, 8($sp)
    addi $sp, $sp, 12
    jr $ra

# rand_int(a0 = n) -> returns pseudo-random integer in [0, n - 1]
rand_int:
    lw $t0, rng_seed
    li $t1, 1103515245
    mul $t0, $t0, $t1
    addi $t0, $t0, 12345
    sw $t0, rng_seed
    srl $t2, $t0, 16
    andi $t2, $t2, 0x7FFF
    remu $v0, $t2, $a0
    jr $ra

# ------------------------------------------------------------------------------
# GRAPHICS & RENDERING PRIMITIVES
# ------------------------------------------------------------------------------
# draw_pixel(a0 = x, a1 = y, a2 = color)
draw_pixel:
    # Bounds check [0, 127]
    bltz $a0, dp_exit
    bge $a0, 128, dp_exit
    bltz $a1, dp_exit
    bge $a1, 128, dp_exit

    # Address = 0x10010000 + ((y * 128) + x) * 4
    sll $t0, $a1, 7        # y * 128
    addu $t0, $t0, $a0     # + x
    sll $t0, $t0, 2        # * 4
    lui $t1, 0x1001
    addu $t1, $t1, $t0
    sw $a2, 0($t1)
dp_exit:
    jr $ra

# fill_rectangle(a0 = x, a1 = y, a2 = w, a3 = h, stack[0] = color)
# Fast scanline blit: direct memory writing with row stride.
fill_rectangle:
    lw $t4, 0($sp)         # color
    blez $a2, fr_exit
    blez $a3, fr_exit
    bltz $a0, fr_exit
    bge $a0, 128, fr_exit
    bltz $a1, fr_exit
    bge $a1, 128, fr_exit

    # Clamp w so x + w <= 128
    addu $t0, $a0, $a2
    ble $t0, 128, fr_w_ok
    li $t1, 128
    subu $a2, $t1, $a0
fr_w_ok:
    # Clamp h so y + h <= 128
    addu $t0, $a1, $a3
    ble $t0, 128, fr_h_ok
    li $t1, 128
    subu $a3, $t1, $a1
fr_h_ok:

    # Start address: 0x10010000 + ((y * 128) + x) * 4
    sll $t0, $a1, 7
    addu $t0, $t0, $a0
    sll $t0, $t0, 2
    lui $t1, 0x1001
    addu $t1, $t1, $t0     # t1 = start_addr

    # Stride = (128 - w) * 4
    li $t2, 128
    subu $t2, $t2, $a2
    sll $t2, $t2, 2        # t2 = stride bytes

    move $t3, $a3          # row_count = h
fr_row_loop:
    blez $t3, fr_exit
    move $t5, $a2          # col_count = w

fr_col_loop:
    blez $t5, fr_next_row
    sw $t4, 0($t1)
    addi $t1, $t1, 4
    addi $t5, $t5, -1
    j fr_col_loop

fr_next_row:
    addu $t1, $t1, $t2     # advance to next scanline start
    addi $t3, $t3, -1
    j fr_row_loop

fr_exit:
    jr $ra

# draw_border(a0 = x, a1 = y, a2 = w, a3 = h, stack[0] = color)
draw_border:
    lw $t4, 0($sp)         # t4 = color
    addi $sp, $sp, -28
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)
    sw $s5, 0($sp)

    move $s0, $a0          # x
    move $s1, $a1          # y
    move $s2, $a2          # w
    move $s3, $a3          # h
    move $s4, $t4          # color

    # Top & bottom horizontal edges
    li $s5, 0              # col = 0..w-1
db_horiz_loop:
    bge $s5, $s2, db_vert_init
    addu $a0, $s0, $s5
    move $a1, $s1          # top: y
    move $a2, $s4
    jal draw_pixel

    addu $a0, $s0, $s5
    addu $a1, $s1, $s3
    addi $a1, $a1, -1      # bottom: y + h - 1
    move $a2, $s4
    jal draw_pixel

    addi $s5, $s5, 1
    j db_horiz_loop

db_vert_init:
    li $s5, 0              # row = 0..h-1
db_vert_loop:
    bge $s5, $s3, db_exit
    move $a0, $s0          # left: x
    addu $a1, $s1, $s5
    move $a2, $s4
    jal draw_pixel

    addu $a0, $s0, $s2
    addi $a0, $a0, -1      # right: x + w - 1
    addu $a1, $s1, $s5
    move $a2, $s4
    jal draw_pixel

    addi $s5, $s5, 1
    j db_vert_loop

db_exit:
    lw $s5, 0($sp)
    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addi $sp, $sp, 28
    jr $ra

# ------------------------------------------------------------------------------
# FONT & TEXT RENDERING
# ------------------------------------------------------------------------------
# draw_character(a0 = x, a1 = y, a2 = ascii_char, a3 = fg_color, stack[0] = bg_color)
draw_character:
    lw $t4, 0($sp)         # t4 = bg_color (-1 = transparent)
    addi $sp, $sp, -28
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)
    sw $s5, 0($sp)

    move $s0, $a0          # x
    move $s1, $a1          # y
    move $s2, $a2          # char
    move $s3, $a3          # fg_color
    move $s4, $t4          # bg_color

    # Convert lowercase 'a'..'z' to uppercase
    blt $s2, 'a', dc_range_check
    bgt $s2, 'z', dc_range_check
    addi $s2, $s2, -32

dc_range_check:
    # Clamp to [32, 90]
    blt $s2, 32, dc_space
    ble $s2, 90, dc_calc_addr
dc_space:
    li $s2, 32

dc_calc_addr:
    addi $s2, $s2, -32     # index = char - 32
    mul $s2, $s2, 5        # offset = index * 5
    la $s5, font_data
    addu $s5, $s5, $s2     # s5 = &font_data[offset]

    li $t5, 0              # row = 0..4
dc_row_loop:
    bge $t5, 5, dc_exit
    lb $t6, 0($s5)         # row bit pattern (3 bits: bits 2, 1, 0)
    addi $s5, $s5, 1

    # Col 0 (bit 2: 0x04)
    addu $a0, $s0, 0
    addu $a1, $s1, $t5
    andi $t7, $t6, 0x04
    bnez $t7, dc_col0_fg
    beq $s4, -1, dc_col1_check
    move $a2, $s4
    jal draw_pixel
    j dc_col1_check
dc_col0_fg:
    move $a2, $s3
    jal draw_pixel

dc_col1_check:
    # Col 1 (bit 1: 0x02)
    addu $a0, $s0, 1
    addu $a1, $s1, $t5
    andi $t7, $t6, 0x02
    bnez $t7, dc_col1_fg
    beq $s4, -1, dc_col2_check
    move $a2, $s4
    jal draw_pixel
    j dc_col2_check
dc_col1_fg:
    move $a2, $s3
    jal draw_pixel

dc_col2_check:
    # Col 2 (bit 0: 0x01)
    addu $a0, $s0, 2
    addu $a1, $s1, $t5
    andi $t7, $t6, 0x01
    bnez $t7, dc_col2_fg
    beq $s4, -1, dc_col3_check
    move $a2, $s4
    jal draw_pixel
    j dc_col3_check
dc_col2_fg:
    move $a2, $s3
    jal draw_pixel

dc_col3_check:
    # Col 3 (horizontal character gap)
    beq $s4, -1, dc_next_row
    addu $a0, $s0, 3
    addu $a1, $s1, $t5
    move $a2, $s4
    jal draw_pixel

dc_next_row:
    addi $t5, $t5, 1
    j dc_row_loop

dc_exit:
    lw $s5, 0($sp)
    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addi $sp, $sp, 28
    jr $ra

# draw_string(a0 = x, a1 = y, a2 = str_ptr, a3 = fg_color, stack[0] = bg_color)
draw_string:
    lw $t4, 0($sp)
    addi $sp, $sp, -28
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)
    sw $s5, 0($sp)

    move $s0, $a0          # current x
    move $s1, $a1          # y
    move $s2, $a2          # str_ptr
    move $s3, $a3          # fg_color
    move $s4, $t4          # bg_color

ds_loop:
    lb $s5, 0($s2)
    beqz $s5, ds_exit
    addi $s2, $s2, 1

    move $a0, $s0
    move $a1, $s1
    move $a2, $s5
    move $a3, $s3
    addi $sp, $sp, -4
    sw $s4, 0($sp)
    jal draw_character
    addi $sp, $sp, 4

    addi $s0, $s0, 4       # advance 4 pixels per character (3 width + 1 gap)
    j ds_loop

ds_exit:
    lw $s5, 0($sp)
    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addi $sp, $sp, 28
    jr $ra

# draw_number(a0 = x, a1 = y, a2 = number, a3 = min_digits, stack[0] = fg, stack[4] = bg)
draw_number:
    lw $t4, 0($sp)         # fg
    lw $t5, 4($sp)         # bg
    addi $sp, $sp, -28
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)
    sw $s5, 0($sp)

    move $s0, $a0          # x
    move $s1, $a1          # y
    move $s2, $a2          # number
    move $s3, $a3          # min_digits
    move $s4, $t4          # fg
    move $s5, $t5          # bg

    # Format into num_buf from back to front
    la $t0, num_buf
    addi $t0, $t0, 20
    sb $zero, 0($t0)       # null terminator
    move $t1, $s2          # remainder
    # Clamp to non-negative
    bgez $t1, dn_val_ok
    li $t1, 0
dn_val_ok:
    move $t2, $s3          # digit counter
    la $t8, num_buf        # lower boundary guard

dn_fmt_loop:
    ble $t0, $t8, dn_fmt_done # prevent buffer underflow
    li $t6, 10
    divu $t1, $t6
    mfhi $t7              # digit 0..9
    mflo $t1              # remaining value
    addi $t7, $t7, 48     # ASCII '0' + digit
    addi $t0, $t0, -1
    sb $t7, 0($t0)
    addi $t2, $t2, -1
    bgtz $t1, dn_fmt_loop
    bgtz $t2, dn_fmt_loop
dn_fmt_done:

    # Now $t0 points to the null-terminated formatted string
    move $a0, $s0
    move $a1, $s1
    move $a2, $t0
    move $a3, $s4
    addi $sp, $sp, -4
    sw $s5, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    lw $s5, 0($sp)
    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addi $sp, $sp, 28
    jr $ra

# ------------------------------------------------------------------------------
# BLOCK & PLAYFIELD DRAWING
# ------------------------------------------------------------------------------
# draw_cell(a0 = board_x, a1 = board_y, a2 = cell_type (0..7), a3 = mode)
#   mode: 0 = MODE_EMPTY, 1 = MODE_LOCKED, 2 = MODE_GHOST, 3 = MODE_ACTIVE
draw_cell:
    # Convert board coords to screen coords:
    # sx = PLAYFIELD_X + board_x * 5
    # sy = PLAYFIELD_Y + board_y * 5
    mul $t0, $a0, 5
    addi $t0, $t0, PLAYFIELD_X
    mul $t1, $a1, 5
    addi $t1, $t1, PLAYFIELD_Y

    # Base address of top-left pixel (sx, sy)
    # addr = 0x10010000 + ((sy * 128) + sx) * 4
    sll $t2, $t1, 7
    addu $t2, $t2, $t0
    sll $t2, $t2, 2
    lui $t3, 0x1001
    addu $t3, $t3, $t2     # t3 = addr of pixel (0, 0)

    # Branch on mode
    beqz $a3, dc_empty
    beq $a3, MODE_GHOST, dc_ghost

    # SOLID / ACTIVE BLOCK (Beveled 3D retro arcade block)
    addi $t4, $a2, -1      # type index 0..6
    sll $t4, $t4, 2
    la $t5, piece_color_base
    addu $t5, $t5, $t4
    lw $t6, 0($t5)         # t6 = base color

    la $t5, piece_color_hi
    addu $t5, $t5, $t4
    lw $t7, 0($t5)         # t7 = highlight color

    la $t5, piece_color_sh
    addu $t5, $t5, $t4
    lw $t8, 0($t5)         # t8 = shadow color

    # Row 0: Highlight (all 5 pixels)
    sw $t7, 0($t3)
    sw $t7, 4($t3)
    sw $t7, 8($t3)
    sw $t7, 12($t3)
    sw $t7, 16($t3)

    # Row 1: (offset +512)
    sw $t7, 512($t3)
    sw $t6, 516($t3)
    sw $t6, 520($t3)
    sw $t6, 524($t3)
    sw $t8, 528($t3)

    # Row 2: (offset +1024)
    sw $t7, 1024($t3)
    sw $t6, 1028($t3)
    sw $t6, 1032($t3)
    sw $t6, 1036($t3)
    sw $t8, 1040($t3)

    # Row 3: (offset +1536)
    sw $t7, 1536($t3)
    sw $t6, 1540($t3)
    sw $t6, 1544($t3)
    sw $t6, 1548($t3)
    sw $t8, 1552($t3)

    # Row 4: Shadow (all 5 pixels, offset +2048)
    sw $t8, 2048($t3)
    sw $t8, 2052($t3)
    sw $t8, 2056($t3)
    sw $t8, 2060($t3)
    sw $t8, 2064($t3)
    jr $ra

dc_ghost:
    # GHOST BLOCK: Wireframe hollow box with ghost color
    addi $t4, $a2, -1      # type index 0..6
    sll $t4, $t4, 2
    la $t5, piece_color_ghost
    addu $t5, $t5, $t4
    lw $t7, 0($t5)         # t7 = ghost color
    li $t8, COLOR_BOARD_BG # t8 = board background

    # Row 0: ghost outline
    sw $t7, 0($t3)
    sw $t7, 4($t3)
    sw $t7, 8($t3)
    sw $t7, 12($t3)
    sw $t7, 16($t3)

    # Row 1:
    sw $t7, 512($t3)
    sw $t8, 516($t3)
    sw $t8, 520($t3)
    sw $t8, 524($t3)
    sw $t7, 528($t3)

    # Row 2:
    sw $t7, 1024($t3)
    sw $t8, 1028($t3)
    sw $t8, 1032($t3)
    sw $t8, 1036($t3)
    sw $t7, 1040($t3)

    # Row 3:
    sw $t7, 1536($t3)
    sw $t8, 1540($t3)
    sw $t8, 1544($t3)
    sw $t8, 1548($t3)
    sw $t7, 1552($t3)

    # Row 4:
    sw $t7, 2048($t3)
    sw $t7, 2052($t3)
    sw $t7, 2056($t3)
    sw $t7, 2060($t3)
    sw $t7, 2064($t3)
    jr $ra

dc_empty:
    # EMPTY CELL: Solid board background
    li $t4, COLOR_BOARD_BG
    sw $t4, 0($t3)
    sw $t4, 4($t3)
    sw $t4, 8($t3)
    sw $t4, 12($t3)
    sw $t4, 16($t3)

    sw $t4, 512($t3)
    sw $t4, 516($t3)
    sw $t4, 520($t3)
    sw $t4, 524($t3)
    sw $t4, 528($t3)

    sw $t4, 1024($t3)
    sw $t4, 1028($t3)
    sw $t4, 1032($t3)
    sw $t4, 1036($t3)
    sw $t4, 1040($t3)

    sw $t4, 1536($t3)
    sw $t4, 1540($t3)
    sw $t4, 1544($t3)
    sw $t4, 1548($t3)
    sw $t4, 1552($t3)

    sw $t4, 2048($t3)
    sw $t4, 2052($t3)
    sw $t4, 2056($t3)
    sw $t4, 2060($t3)
    sw $t4, 2064($t3)
    jr $ra

# draw_tetromino(a0 = type, a1 = rot, a2 = board_x, a3 = board_y, stack[0] = mode)
# Draws all 4 blocks of the specified tetromino.
# Preserves $s0..$s6 across subroutine calls (draw_cell clobbers $t registers).
draw_tetromino:
    lw $t4, 0($sp)         # mode
    addi $sp, $sp, -32
    sw $ra, 28($sp)
    sw $s0, 24($sp)
    sw $s1, 20($sp)
    sw $s2, 16($sp)
    sw $s3, 12($sp)
    sw $s4, 8($sp)
    sw $s5, 4($sp)
    sw $s6, 0($sp)

    move $s0, $a0          # type (0..6)
    move $s1, $a1          # rot
    move $s2, $a2          # board_x
    move $s3, $a3          # board_y
    move $s4, $t4          # mode

    # Offset table pointer: piece_offsets + (type * 32) + (rot * 8)
    sll $t0, $s0, 5
    sll $t1, $s1, 3
    addu $t0, $t0, $t1
    la $s5, piece_offsets
    addu $s5, $s5, $t0

    li $s6, 0              # block index i = 0..3 (callee-saved across draw_cell)
dt_loop:
    bge $s6, 4, dt_exit
    lb $t6, 0($s5)         # dx
    lb $t7, 1($s5)         # dy
    addi $s5, $s5, 2
    addi $s6, $s6, 1

    addu $a0, $s2, $t6     # bx = board_x + dx
    addu $a1, $s3, $t7     # by = board_y + dy

    # Only draw if inside playfield (0 <= bx < 10, 0 <= by < 20)
    bltz $a1, dt_loop
    bge $a1, 20, dt_loop
    bltz $a0, dt_loop
    bge $a0, 10, dt_loop

    addi $a2, $s0, 1       # cell_type = type + 1
    move $a3, $s4          # mode
    jal draw_cell
    j dt_loop

dt_exit:
    lw $s6, 0($sp)
    lw $s5, 4($sp)
    lw $s4, 8($sp)
    lw $s3, 12($sp)
    lw $s2, 16($sp)
    lw $s1, 20($sp)
    lw $s0, 24($sp)
    lw $ra, 28($sp)
    addi $sp, $sp, 32
    jr $ra

# draw_board: renders the 10x20 board array
draw_board:
    addi $sp, $sp, -16
    sw $ra, 12($sp)
    sw $s0, 8($sp)
    sw $s1, 4($sp)
    sw $s2, 0($sp)

    # Fast clear playfield interior using scanline fill_rectangle
    li $a0, PLAYFIELD_X
    li $a1, PLAYFIELD_Y
    li $a2, PLAYFIELD_W
    li $a3, PLAYFIELD_H
    li $t0, COLOR_BOARD_BG
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    # Only draw occupied locked cells
    la $s2, board
    li $s0, 0              # y = 0..19
dboard_y_loop:
    bge $s0, 20, dboard_exit
    li $s1, 0              # x = 0..9
dboard_x_loop:
    bge $s1, 10, dboard_next_y
    lb $t0, 0($s2)         # cell value (0..7)
    addi $s2, $s2, 1

    beqz $t0, dboard_next_x # Skip empty cells! (Already filled with COLOR_BOARD_BG)

    move $a0, $s1          # board_x
    move $a1, $s0          # board_y
    move $a2, $t0          # cell_type
    li $a3, MODE_LOCKED
    jal draw_cell

dboard_next_x:
    addi $s1, $s1, 1
    j dboard_x_loop

dboard_next_y:
    addi $s0, $s0, 1
    j dboard_y_loop

dboard_exit:
    lw $s2, 0($sp)
    lw $s1, 4($sp)
    lw $s0, 8($sp)
    lw $ra, 12($sp)
    addi $sp, $sp, 16
    jr $ra

# draw_ghost_piece: predicts landing row and draws wireframe ghost
draw_ghost_piece:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    jal calculate_ghost_y

    # If ghost position matches active position, don't draw ghost underneath
    lw $t0, curr_y
    lw $t1, ghost_y
    beq $t1, $t0, dgp_exit

    # Draw ghost tetromino
    lw $a0, curr_type
    lw $a1, curr_rot
    lw $a2, curr_x
    lw $a3, ghost_y
    li $t1, MODE_GHOST
    addi $sp, $sp, -4
    sw $t1, 0($sp)
    jal draw_tetromino
    addi $sp, $sp, 4

dgp_exit:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# draw_active_piece: draws active falling tetromino
draw_active_piece:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $a0, curr_type
    lw $a1, curr_rot
    lw $a2, curr_x
    lw $a3, curr_y
    li $t0, MODE_ACTIVE
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_tetromino
    addi $sp, $sp, 4

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# HUD & PREVIEW RENDERING
# ------------------------------------------------------------------------------
# draw_hud: renders static playfield borders, labels, and boxes
draw_hud:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # 1. Fill entire 128x128 screen with dark background
    li $a0, 0
    li $a1, 0
    li $a2, 128
    li $a3, 128
    li $t0, COLOR_BG
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    # 2. Outer playfield border: (8, 12, 54, 104)
    li $a0, 8
    li $a1, 12
    li $a2, 54
    li $a3, 104
    li $t0, COLOR_BORDER
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_border
    addi $sp, $sp, 4

    # 3. Inner playfield border highlight: (9, 13, 52, 102)
    li $a0, 9
    li $a1, 13
    li $a2, 52
    li $a3, 102
    li $t0, COLOR_BORDER_HI
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_border
    addi $sp, $sp, 4

    # 4. Fill playfield interior with black: (10, 14, 50, 100)
    li $a0, 10
    li $a1, 14
    li $a2, 50
    li $a3, 100
    li $t0, COLOR_BOARD_BG
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    # 5. Header Title "TETRIS"
    li $a0, 84
    li $a1, 6
    la $a2, str_title
    li $a3, COLOR_TEXT_YELLOW
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    # Separator Line at Y = 13
    li $a0, 68
    li $a1, 13
    li $a2, 54
    li $a3, 1
    li $t0, COLOR_BORDER
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    # Labels: SCORE, HIGH, LEVEL, LINES
    li $a0, 68
    li $a1, 17
    la $a2, str_score
    li $a3, COLOR_TEXT_WHITE
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    li $a0, 68
    li $a1, 25
    la $a2, str_high
    li $a3, COLOR_TEXT_WHITE
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    li $a0, 68
    li $a1, 33
    la $a2, str_level
    li $a3, COLOR_TEXT_WHITE
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    li $a0, 68
    li $a1, 41
    la $a2, str_lines
    li $a3, COLOR_TEXT_WHITE
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    # Separator Line at Y = 49
    li $a0, 68
    li $a1, 49
    li $a2, 54
    li $a3, 1
    li $t0, COLOR_BORDER
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    # "NEXT" label
    li $a0, 68
    li $a1, 53
    la $a2, str_next
    li $a3, COLOR_TEXT_WHITE
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    # Next-piece preview box border: (82, 53, 28, 24)
    li $a0, 82
    li $a1, 53
    li $a2, 28
    li $a3, 24
    li $t0, COLOR_BORDER
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_border
    addi $sp, $sp, 4

    # Separator Line at Y = 81
    li $a0, 68
    li $a1, 81
    li $a2, 54
    li $a3, 1
    li $t0, COLOR_BORDER
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    # "CONTROLS" header
    li $a0, 74
    li $a1, 85
    la $a2, str_ctrl_head
    li $a3, COLOR_TEXT_YELLOW
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    # Controls references
    li $a0, 68
    li $a1, 93
    la $a2, str_ctrl_move
    li $a3, COLOR_TEXT_GRAY
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    li $a0, 68
    li $a1, 100
    la $a2, str_ctrl_rot
    li $a3, COLOR_TEXT_GRAY
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    li $a0, 68
    li $a1, 107
    la $a2, str_ctrl_drop
    li $a3, COLOR_TEXT_GRAY
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    li $a0, 68
    li $a1, 114
    la $a2, str_ctrl_pause
    li $a3, COLOR_TEXT_GRAY
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    li $a0, 68
    li $a1, 121
    la $a2, str_ctrl_rst
    li $a3, COLOR_TEXT_GRAY
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# update_dynamic_hud: draws current score, high score, level, lines
update_dynamic_hud:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Score (6 digits, cyan)
    li $a0, 92
    li $a1, 17
    lw $a2, score
    li $a3, 6
    li $t0, COLOR_TEXT_CYAN
    li $t1, COLOR_BG
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal draw_number
    addi $sp, $sp, 8

    # High score (6 digits, cyan)
    li $a0, 92
    li $a1, 25
    lw $a2, high_score
    li $a3, 6
    li $t0, COLOR_TEXT_CYAN
    li $t1, COLOR_BG
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal draw_number
    addi $sp, $sp, 8

    # Level (2 digits, yellow)
    li $a0, 104
    li $a1, 33
    lw $a2, level
    li $a3, 2
    li $t0, COLOR_TEXT_YELLOW
    li $t1, COLOR_BG
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal draw_number
    addi $sp, $sp, 8

    # Lines (3 digits, yellow)
    li $a0, 100
    li $a1, 41
    lw $a2, lines
    li $a3, 3
    li $t0, COLOR_TEXT_YELLOW
    li $t1, COLOR_BG
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal draw_number
    addi $sp, $sp, 8

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# draw_next_preview: centers and renders the upcoming tetromino in preview box
draw_next_preview:
    addi $sp, $sp, -16
    sw $ra, 12($sp)
    sw $s0, 8($sp)
    sw $s1, 4($sp)
    sw $s2, 0($sp)

    # Clear preview box interior: (84, 55, 24, 20) with COLOR_BOARD_BG
    li $a0, 84
    li $a1, 55
    li $a2, 24
    li $a3, 20
    li $t0, COLOR_BOARD_BG
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    lw $s0, next_type      # s0 = next piece type (0..6)

    # Offset table pointer for rotation 0
    sll $t0, $s0, 5        # type * 32
    la $s1, piece_offsets
    addu $s1, $s1, $t0     # s1 = &piece_offsets[next_type][0][0]

    # Base coordinates for centering in the 24x20 box
    # Default top-left within box: sx = 88, sy = 60
    li $s2, 88             # base_sx
    li $t1, 60             # base_sy

    # Custom centering adjustments:
    # Piece 0 (I): horizontal 4-bar -> sx = 86, sy = 62
    bnez $s0, dnp_check_o
    li $s2, 86
    li $t1, 62
    j dnp_draw_blocks

dnp_check_o:
    # Piece 1 (O): 2x2 square -> sx = 85, sy = 60
    li $t2, 1
    bne $s0, $t2, dnp_draw_blocks
    li $s2, 85
    li $t1, 60

dnp_draw_blocks:
    li $t2, 0              # i = 0..3
dnp_loop:
    bge $t2, 4, dnp_exit
    lb $t3, 0($s1)         # dx
    lb $t4, 1($s1)         # dy
    addi $s1, $s1, 2
    addi $t2, $t2, 1

    # Screen coordinates for block:
    # px = base_sx + dx * 5
    # py = base_sy + dy * 5
    mul $t5, $t3, 5
    addu $t5, $s2, $t5     # px
    mul $t6, $t4, 5
    addu $t6, $t1, $t6     # py

    # Draw solid 5x5 beveled cell directly at pixel (px, py)
    sll $t7, $t6, 7
    addu $t7, $t7, $t5
    sll $t7, $t7, 2
    lui $t8, 0x1001
    addu $t8, $t8, $t7     # t8 = addr

    sll $t9, $s0, 2
    la $t0, piece_color_base
    addu $t0, $t0, $t9
    lw $t0, 0($t0)         # base

    la $t3, piece_color_hi
    addu $t3, $t3, $t9
    lw $t3, 0($t3)         # hi

    la $t4, piece_color_sh
    addu $t4, $t4, $t9
    lw $t4, 0($t4)         # sh

    # Row 0: Highlight
    sw $t3, 0($t8)
    sw $t3, 4($t8)
    sw $t3, 8($t8)
    sw $t3, 12($t8)
    sw $t3, 16($t8)

    # Row 1:
    sw $t3, 512($t8)
    sw $t0, 516($t8)
    sw $t0, 520($t8)
    sw $t0, 524($t8)
    sw $t4, 528($t8)

    # Row 2:
    sw $t3, 1024($t8)
    sw $t0, 1028($t8)
    sw $t0, 1032($t8)
    sw $t0, 1036($t8)
    sw $t4, 1040($t8)

    # Row 3:
    sw $t3, 1536($t8)
    sw $t0, 1540($t8)
    sw $t0, 1544($t8)
    sw $t0, 1548($t8)
    sw $t4, 1552($t8)

    # Row 4: Shadow
    sw $t4, 2048($t8)
    sw $t4, 2052($t8)
    sw $t4, 2056($t8)
    sw $t4, 2060($t8)
    sw $t4, 2064($t8)

    j dnp_loop

dnp_exit:
    lw $s2, 0($sp)
    lw $s1, 4($sp)
    lw $s0, 8($sp)
    lw $ra, 12($sp)
    addi $sp, $sp, 16
    jr $ra

# ------------------------------------------------------------------------------
# OVERLAY SCREENS: PAUSE & GAME OVER
# ------------------------------------------------------------------------------
# draw_pause_screen: renders modal pause banner over the playfield
draw_pause_screen:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Overlay box: (14, 52, 42, 22)
    li $a0, 14
    li $a1, 52
    li $a2, 42
    li $a3, 22
    li $t0, COLOR_OVERLAY_BG
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    li $a0, 14
    li $a1, 52
    li $a2, 42
    li $a3, 22
    li $t0, COLOR_BORDER_HI
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_border
    addi $sp, $sp, 4

    # Text: "PAUSED"
    li $a0, 23
    li $a1, 56
    la $a2, str_paused_title
    li $a3, COLOR_TEXT_YELLOW
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    # Text: "PRESS P"
    li $a0, 21
    li $a1, 64
    la $a2, str_paused_sub
    li $a3, COLOR_TEXT_WHITE
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# draw_game_over_screen: renders modal game-over banner over the playfield
draw_game_over_screen:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Overlay box: (12, 44, 46, 36)
    li $a0, 12
    li $a1, 44
    li $a2, 46
    li $a3, 36
    li $t0, COLOR_OVERLAY_RED
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal fill_rectangle
    addi $sp, $sp, 4

    li $a0, 12
    li $a1, 44
    li $a2, 46
    li $a3, 36
    li $t0, 0x00FF3030     # Bright red border
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_border
    addi $sp, $sp, 4

    # Text: "GAME OVER"
    li $a0, 17
    li $a1, 48
    la $a2, str_gameover_head
    li $a3, 0x00FF4040     # Red text
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    # Text: "SCORE:"
    li $a0, 16
    li $a1, 57
    la $a2, str_final_score
    li $a3, COLOR_TEXT_WHITE
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    # Final score number
    li $a0, 16
    li $a1, 64
    lw $a2, score
    li $a3, 6
    li $t0, COLOR_TEXT_CYAN
    li $t1, COLOR_OVERLAY_RED
    addi $sp, $sp, -8
    sw $t0, 0($sp)
    sw $t1, 4($sp)
    jal draw_number
    addi $sp, $sp, 8

    # Text: "PRESS R"
    li $a0, 21
    li $a1, 72
    la $a2, str_restart_sub
    li $a3, COLOR_TEXT_YELLOW
    li $t0, -1
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    jal draw_string
    addi $sp, $sp, 4

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# RENDER FRAME DISPATCHER
# ------------------------------------------------------------------------------
# render_frame: blits updated gameplay board and HUD when dirty
render_frame:
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Only redraw playfield when in PLAYING state
    lw $t0, game_state
    bne $t0, STATE_PLAYING, rf_check_hud

    lw $t1, needs_redraw
    beqz $t1, rf_check_hud

    # Redraw board, ghost piece, active piece
    jal draw_board
    jal draw_ghost_piece
    jal draw_active_piece

    sw $zero, needs_redraw

rf_check_hud:
    lw $t2, hud_needs_redraw
    beqz $t2, rf_heartbeat

    jal update_dynamic_hud
    jal draw_next_preview
    sw $zero, hud_needs_redraw

rf_heartbeat:
    # Visual Heartbeat Indicator at (124, 2):
    # Conclusively proves the game loop is ticking and distinguishes from MMIO focus loss
    lw $t3, frame_counter
    addi $t3, $t3, 1
    sw $t3, frame_counter
    andi $t4, $t3, 32
    li $t5, 0x0000FF55     # Bright green (active phase)
    beqz $t4, rf_draw_hb
    li $t5, 0x00003010     # Dark forest green (blink phase)
rf_draw_hb:
    lui $t6, 0x1001
    sw $t5, 0x05F0($t6)
    sw $t5, 0x05F4($t6)
    sw $t5, 0x07F0($t6)
    sw $t5, 0x07F4($t6)

rf_done:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra
