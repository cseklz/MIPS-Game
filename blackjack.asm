# ==============================================================================
# BALATRO BLACKJACK - COMPLETE MIPS32 IMPLEMENTATION FOR MARS 4.5
# ==============================================================================
#
# A complete, self-contained, retro pixel-art Blackjack game for MARS 4.5
# featuring Balatro-inspired visual presentation: deep teal table felt,
# dark charcoal panels, a 24x24 pixel-art dealer portrait (Jimbo), custom
# playing cards with ranks, suit symbols and patterned card backs, chunky
# drop-shadowed typography, persistent keyboard control strip, and complete
# game logic (Fisher-Yates shuffle, natural blackjacks, multi-ace handling,
# automated dealer soft/hard 17 logic, session statistics).
#
# BITMAP DISPLAY CONFIGURATION (MARS -> Tools -> Bitmap Display):
# ------------------------------------------------------------------------------
#   - Unit Width in Pixels:     4
#   - Unit Height in Pixels:    4
#   - Display Width in Pixels:  1024
#   - Display Height in Pixels: 512
#   - Base address for display: 0x10010000 (static data)
#
#   => Logical Drawing Surface: 256 x 128 pixels.
#   => Framebuffer Allocation:  131,072 bytes (0x10010000 .. 0x1002FFFF)
#   => IMPORTANT: Click "Connect to MIPS" BEFORE running the program!
#
# KEYBOARD SIMULATOR CONFIGURATION (MARS -> Tools -> Keyboard and Display MMIO):
# ------------------------------------------------------------------------------
#   1. Open Tools -> "Keyboard and Display MMIO Simulator"
#   2. Click "Connect to MIPS"
#   3. CRITICAL: Click into the bottom text area labeled "Keyboard" to focus it!
#      Keystrokes must be typed directly into this text area.
#
# CONTROLS:
# ------------------------------------------------------------------------------
#   [N] / [n] : Deal first hand / Start next round (Opening and Result screens)
#   [H] / [h] : Hit (Player turn)
#   [S] / [s] : Stand (Player turn)
#   [R] / [r] : Reset session statistics and return to opening title screen
#   [Q] / [q] : Quit game
#
# ==============================================================================

# ==============================================================================
# CONSTANTS & DEFINITIONS
# ==============================================================================

# Game States
.eqv STATE_OPENING       0      # Title screen awaiting initial deal
.eqv STATE_PLAYER_TURN   1      # Player can Hit [H] or Stand [S]
.eqv STATE_DEALER_TURN   2      # Dealer automated hit/stand loop
.eqv STATE_ROUND_OVER    3      # Outcome resolved, awaiting [N] or [R]

# Result Codes
.eqv RES_NONE            0      # No result yet
.eqv RES_PLAYER_BJ       1      # Player natural blackjack!
.eqv RES_DEALER_BJ       2      # Dealer natural blackjack
.eqv RES_PUSH_BJ         3      # Both player and dealer natural blackjack
.eqv RES_PLAYER_BUST     4      # Player exceeded 21
.eqv RES_DEALER_BUST     5      # Dealer exceeded 21
.eqv RES_PLAYER_WIN      6      # Player higher total than dealer
.eqv RES_DEALER_WIN      7      # Dealer higher total than player
.eqv RES_PUSH            8      # Equal hand totals (push / tie)

# Display Dimensions
.eqv SCREEN_WIDTH        256
.eqv SCREEN_HEIGHT       128
.eqv FRAMEBUFFER_BASE    0x10010000

# MMIO Registers
.eqv MMIO_RECV_CTRL      0xffff0000
.eqv MMIO_RECV_DATA      0xffff0004

# Balatro Color Palette (0x00RRGGBB)
.eqv COLOR_FELT_BG         0x00173B32   # Deep teal felt table
.eqv COLOR_FELT_STITCH     0x0027584C   # Felt stitching accent
.eqv COLOR_PANEL_BG        0x001B1E26   # Dark charcoal slate panels
.eqv COLOR_PANEL_BORDER    0x00323948   # Charcoal panel borders
.eqv COLOR_PANEL_SHADOW    0x000E1015   # Deep drop shadow
.eqv COLOR_GOLD            0x00FDB827   # Balatro Gold accent
.eqv COLOR_GOLD_SHADOW     0x00A06E10   # Gold button bevel shadow
.eqv COLOR_CYAN            0x0000D2BE   # Electric Balatro Cyan
.eqv COLOR_CYAN_SHADOW     0x0000786C   # Cyan button bevel shadow
.eqv COLOR_CORAL           0x00FE5F55   # Balatro Coral / Red
.eqv COLOR_CORAL_SHADOW    0x00A02620   # Coral button bevel shadow
.eqv COLOR_PURPLE          0x00A06CD5   # Balatro Purple accent
.eqv COLOR_PURPLE_SHADOW   0x005E3288   # Purple button bevel shadow
.eqv COLOR_WHITE           0x00FFFFFF   # Crisp white
.eqv COLOR_CREAM           0x00E8E2D2   # Warm vintage cream text
.eqv COLOR_TEXT_DIM        0x00555F70   # Muted slate text for disabled UI
.eqv COLOR_BTN_INACTIVE_BG 0x00222630   # Inactive button background
.eqv COLOR_BTN_INACTIVE_BD 0x002E3442   # Inactive button border

# Card Colors
.eqv COLOR_CARD_FACE       0x00FFF8E8   # Warm vintage cream card face
.eqv COLOR_CARD_BORDER     0x00231F1C   # Crisp dark card outline
.eqv COLOR_CARD_SHADOW     0x000D221D   # Card drop shadow on felt
.eqv COLOR_CARD_BACK_BASE  0x00D94236   # Patterned back coral red
.eqv COLOR_CARD_BACK_LINE  0x00FE9F45   # Patterned back bright orange
.eqv COLOR_CARD_BACK_EMBL  0x002B66B1   # Patterned back blue diamond emblem
.eqv COLOR_SUIT_RED        0x00E2283C   # Hearts / Diamonds vibrant red
.eqv COLOR_SUIT_BLACK      0x0022242B   # Spades / Clubs deep charcoal

# ==============================================================================
# DATA SEGMENT
# ==============================================================================
.data

# ------------------------------------------------------------------------------
# 1. FRAMEBUFFER RESERVATION (131,072 BYTES = 256 x 128 WORDS)
# ------------------------------------------------------------------------------
# Must be the very first object in .data to guarantee placement at 0x10010000.
framebuffer:        .space 131072

# ------------------------------------------------------------------------------
# 2. GAME STATE VARIABLES (Placed safely after 0x1002FFFF)
# ------------------------------------------------------------------------------
.align 2
game_state:         .word 0       # Current state (STATE_OPENING .. STATE_ROUND_OVER)
stat_wins:          .word 0       # Player win counter
stat_losses:        .word 0       # Player loss counter
stat_pushes:        .word 0       # Push / tie counter
stat_rounds:        .word 0       # Total rounds played
result_code:        .word 0       # Current round outcome code (RES_NONE .. RES_PUSH)
dealer_hole_hidden: .word 1       # 1 = dealer hole card face-down, 0 = revealed
player_score:       .word 0       # Evaluated player hand score
dealer_score:       .word 0       # Evaluated dealer hand score
deck_index:         .word 0       # Top-of-deck pointer (0..51)
player_card_count:  .word 0       # Cards currently in player hand (0..16)
dealer_card_count:  .word 0       # Cards currently in dealer hand (0..16)

# Card Arrays (each entry is an integer card ID 0..51)
deck:               .word 0:52    # 52-card deck
player_hand:        .word 0:16    # Player hand cards
dealer_hand:        .word 0:16    # Dealer hand cards

# Scratch string buffer for number conversion
num_str_buf:        .space 16

# ------------------------------------------------------------------------------
# 3. GRAPHICS DATA: PALETTES, SPRITES & BITMAPS
# ------------------------------------------------------------------------------
.align 2
# Dealer portrait palette (8 colors for indexed sprite)
portrait_palette:
    .word 0x001B1E26   # 0: Background dark slate
    .word 0x00111216   # 1: Dark outline
    .word 0x00D9383A   # 2: Jester Cap / Jacket Red
    .word 0x002B66B1   # 3: Jester Cap / Jacket Blue
    .word 0x00F8B820   # 4: Jester Gold / Bell
    .word 0x00FED5B0   # 5: Peach Skin
    .word 0x00F29486   # 6: Rosy Cheeks
    .word 0x00FFFFFF   # 7: White / Collar

# 24x24 Pixel-art dealer portrait (Jimbo) - 576 bytes
dealer_sprite:
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0  # row 0
    .byte 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 0, 0, 0, 0, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0  # row 1
    .byte 0, 0, 0, 0, 0, 0, 0, 2, 2, 1, 0, 0, 0, 0, 1, 3, 3, 0, 0, 0, 0, 0, 0, 0  # row 2
    .byte 0, 0, 0, 0, 0, 0, 2, 2, 2, 1, 0, 0, 0, 0, 1, 3, 3, 3, 0, 0, 0, 0, 0, 0  # row 3
    .byte 0, 0, 0, 0, 0, 2, 2, 2, 2, 1, 0, 0, 0, 0, 1, 3, 3, 3, 3, 0, 0, 0, 0, 0  # row 4
    .byte 0, 0, 0, 0, 2, 2, 2, 2, 1, 1, 0, 0, 0, 0, 1, 1, 3, 3, 3, 3, 0, 0, 0, 0  # row 5
    .byte 0, 0, 0, 4, 1, 2, 2, 2, 2, 2, 1, 1, 1, 1, 3, 3, 3, 3, 3, 1, 4, 0, 0, 0  # row 6
    .byte 0, 0, 4, 4, 1, 2, 2, 2, 2, 2, 2, 1, 1, 3, 3, 3, 3, 3, 3, 1, 4, 4, 0, 0  # row 7
    .byte 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 3, 3, 3, 3, 1, 1, 1, 1, 0, 0, 0  # row 8
    .byte 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0  # row 9
    .byte 0, 0, 0, 0, 1, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 1, 0, 0, 0, 0  # row 10
    .byte 0, 0, 0, 0, 1, 5, 1, 7, 1, 5, 5, 5, 5, 5, 5, 1, 7, 1, 5, 1, 0, 0, 0, 0  # row 11
    .byte 0, 0, 0, 0, 1, 5, 1, 1, 1, 5, 5, 6, 5, 5, 5, 1, 1, 1, 5, 1, 0, 0, 0, 0  # row 12
    .byte 0, 0, 0, 0, 1, 5, 6, 6, 5, 5, 5, 1, 1, 5, 5, 5, 6, 6, 5, 1, 0, 0, 0, 0  # row 13
    .byte 0, 0, 0, 0, 1, 5, 5, 5, 5, 1, 7, 7, 7, 7, 1, 5, 5, 5, 5, 1, 0, 0, 0, 0  # row 14
    .byte 0, 0, 0, 0, 0, 1, 5, 5, 5, 5, 1, 1, 1, 1, 5, 5, 5, 5, 1, 0, 0, 0, 0, 0  # row 15
    .byte 0, 0, 0, 0, 0, 0, 1, 1, 5, 5, 5, 5, 5, 5, 5, 5, 1, 1, 0, 0, 0, 0, 0, 0  # row 16
    .byte 0, 0, 0, 0, 0, 1, 7, 1, 7, 1, 7, 1, 7, 1, 7, 1, 7, 1, 0, 0, 0, 0, 0, 0  # row 17
    .byte 0, 0, 0, 0, 1, 7, 7, 1, 7, 7, 1, 7, 7, 1, 7, 7, 1, 7, 7, 1, 0, 0, 0, 0  # row 18
    .byte 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0  # row 19
    .byte 0, 0, 0, 1, 2, 2, 2, 2, 1, 4, 4, 4, 4, 1, 3, 3, 3, 3, 3, 1, 0, 0, 0, 0  # row 20
    .byte 0, 0, 1, 2, 2, 2, 2, 2, 1, 4, 4, 4, 4, 1, 3, 3, 3, 3, 3, 3, 1, 0, 0, 0  # row 21
    .byte 0, 0, 1, 2, 2, 2, 2, 2, 1, 4, 4, 4, 4, 1, 3, 3, 3, 3, 3, 3, 1, 0, 0, 0  # row 22
    .byte 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0  # row 23

# 5x5 Suit bitmaps (Spade, Heart, Club, Diamond) - 5 bytes each
suit_5x5_data:
    .byte 0x04, 0x0E, 0x1F, 0x15, 0x04  # 0: Spade
    .byte 0x0A, 0x1F, 0x1F, 0x0E, 0x04  # 1: Heart
    .byte 0x04, 0x0E, 0x1F, 0x04, 0x0E  # 2: Club
    .byte 0x04, 0x0E, 0x1F, 0x0E, 0x04  # 3: Diamond

# 7x7 Center card icons (Spade, Heart, Club, Diamond, Crown) - 7 bytes each
icon_7x7_data:
    .byte 0x08, 0x1C, 0x3E, 0x7F, 0x7F, 0x6B, 0x08  # 0: Spade
    .byte 0x36, 0x7F, 0x7F, 0x7F, 0x3E, 0x1C, 0x08  # 1: Heart
    .byte 0x08, 0x1C, 0x3E, 0x7F, 0x7F, 0x08, 0x1C  # 2: Club
    .byte 0x08, 0x1C, 0x3E, 0x7F, 0x3E, 0x1C, 0x08  # 3: Diamond
    .byte 0x55, 0x7F, 0x5D, 0x7F, 0x3E, 0x1C, 0x3E  # 4: Royal Crown (court cards)

# Rank ASCII characters for cards 0..12
rank_chars:
    .byte 'A', '2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K'

# Complete 3x5 font table (ASCII 32 to 93, 62 characters * 5 bytes = 310 bytes)
font_data:
    .byte 0x00, 0x00, 0x00, 0x00, 0x00  # 32: SPACE
    .byte 0x02, 0x02, 0x02, 0x00, 0x02  # 33: !
    .byte 0x05, 0x05, 0x00, 0x00, 0x00  # 34: "
    .byte 0x05, 0x07, 0x05, 0x07, 0x05  # 35: #
    .byte 0x02, 0x07, 0x06, 0x07, 0x02  # 36: $
    .byte 0x05, 0x01, 0x02, 0x04, 0x05  # 37: %
    .byte 0x02, 0x05, 0x02, 0x05, 0x03  # 38: &
    .byte 0x02, 0x02, 0x00, 0x00, 0x00  # 39: '
    .byte 0x01, 0x02, 0x02, 0x02, 0x01  # 40: (
    .byte 0x04, 0x02, 0x02, 0x02, 0x04  # 41: )
    .byte 0x05, 0x02, 0x07, 0x02, 0x05  # 42: *
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
    .byte 0x06, 0x01, 0x02, 0x00, 0x02  # 63: ?
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
    .byte 0x06, 0x04, 0x04, 0x04, 0x06  # 91: [
    .byte 0x04, 0x04, 0x02, 0x01, 0x01  # 92: \
    .byte 0x03, 0x01, 0x01, 0x01, 0x03  # 93: ]

# ------------------------------------------------------------------------------
# 4. UI TEXT STRINGS
# ------------------------------------------------------------------------------
str_dealer_lbl:    .asciiz "DEALER"
str_player_lbl:    .asciiz "PLAYER"
str_dealer_hand:   .asciiz "DEALER HAND"
str_player_hand:   .asciiz "PLAYER HAND"
str_stats_title:   .asciiz "* STATS *"
str_wins_lbl:      .asciiz "WINS:"
str_loss_lbl:      .asciiz "LOSS:"
str_push_lbl:      .asciiz "PUSH:"
str_rnds_lbl:      .asciiz "RNDS:"

str_score_dash:    .asciiz "[ - ]"
str_score_hide:    .asciiz "[ ? ]"
str_score_tot:     .asciiz "TOTAL: "
str_score_bust:    .asciiz "BUST "
str_score_bj:      .asciiz "BJ 21"

# Middle Banner Messages
str_msg_welcome:   .asciiz "* BALATRO BLACKJACK * PRESS [N] TO DEAL"
str_msg_player:    .asciiz "YOUR TURN -> [H] HIT  OR  [S] STAND"
str_msg_dealer:    .asciiz "DEALER'S TURN... DRAWING CARDS"
str_msg_pj_bj:     .asciiz "* NATURAL BLACKJACK! PLAYER WINS! *"
str_msg_dl_bj:     .asciiz "DEALER HAS BLACKJACK! DEALER WINS!"
str_msg_ps_bj:     .asciiz "BOTH HAVE BLACKJACK! ROUND IS A PUSH!"
str_msg_pj_bust:   .asciiz "PLAYER BUST! OVER 21! DEALER WINS!"
str_msg_dl_bust:   .asciiz "DEALER BUSTS! PLAYER WINS THE ROUND!"
str_msg_pj_win:    .asciiz "PLAYER WINS! HIGHER HAND TOTAL!"
str_msg_dl_win:    .asciiz "DEALER WINS! HIGHER HAND TOTAL!"
str_msg_push:      .asciiz "PUSH! EQUAL HANDS - IT'S A TIE!"

# Control Buttons
str_btn_deal:      .asciiz "[N] DEAL"
str_btn_hit:       .asciiz "[H] HIT"
str_btn_stand:     .asciiz "[S] STAND"
str_btn_reset:     .asciiz "[R] RESET"
str_btn_quit:      .asciiz "[Q] QUIT"

# ==============================================================================
# TEXT SEGMENT (PROGRAM CODE)
# ==============================================================================
.text
.globl main

# ------------------------------------------------------------------------------
# ROUTINE: main
# Purpose: Program entry point. Initializes RNG, resets session, and enters loop.
# ------------------------------------------------------------------------------
main:
    # Seed MARS random number generator (id 0) with system time
    li $v0, 30             # syscall 30: get time
    syscall
    move $a1, $a0          # seed = lower 32 bits of time
    li $a0, 0              # rng id = 0
    li $v0, 40             # syscall 40: set seed
    syscall

    # Initialize session statistics
    sw $zero, stat_wins
    sw $zero, stat_losses
    sw $zero, stat_pushes
    sw $zero, stat_rounds
    sw $zero, result_code
    sw $zero, player_card_count
    sw $zero, dealer_card_count
    sw $zero, player_score
    sw $zero, dealer_score

    # Set opening state
    li $t0, STATE_OPENING
    sw $t0, game_state

    # Paint initial screen
    jal render_screen

# ------------------------------------------------------------------------------
# ROUTINE: main_loop
# Purpose: Non-blocking MMIO input poll loop. Keeps CPU cool and responds to keys.
# ------------------------------------------------------------------------------
main_loop:
    # Small sleep slice (16 ms) to prevent high host CPU usage
    li $v0, 32
    li $a0, 16
    syscall

    # Poll MMIO Receiver Control (0xffff0000)
    li $t0, MMIO_RECV_CTRL
    lw $t1, 0($t0)
    andi $t1, $t1, 1
    beqz $t1, main_loop

    # Character ready! Read Receiver Data (0xffff0004)
    lw $a0, 4($t0)

    # Dispatch key input
    jal handle_key_input
    j main_loop

# ------------------------------------------------------------------------------
# ROUTINE: handle_key_input
# Inputs:  $a0 = raw ASCII character
# Purpose: Normalizes case and executes valid actions according to game state.
# ------------------------------------------------------------------------------
handle_key_input:
    addiu $sp, $sp, -8
    sw $ra, 4($sp)
    sw $s0, 0($sp)

    move $s0, $a0          # s0 = key

    # Normalize lowercase letters ('a'..'z' -> 'A'..'Z')
    blt $s0, 97, hki_check_quit
    bgt $s0, 122, hki_check_quit
    addiu $s0, $s0, -32

hki_check_quit:
    # 'Q' quits in any state
    bne $s0, 'Q', hki_check_state
    li $v0, 10             # syscall 10: terminate simulation
    syscall

hki_check_state:
    lw $t0, game_state

    beq $t0, STATE_OPENING, hki_opening
    beq $t0, STATE_PLAYER_TURN, hki_player_turn
    beq $t0, STATE_ROUND_OVER, hki_round_over
    j hki_done             # In STATE_DEALER_TURN, all input is ignored

hki_opening:
    beq $s0, 'N', hki_do_deal
    beq $s0, 'R', hki_do_reset
    j hki_done

hki_player_turn:
    beq $s0, 'H', hki_do_hit
    beq $s0, 'S', hki_do_stand
    j hki_done

hki_round_over:
    beq $s0, 'N', hki_do_deal
    beq $s0, 'R', hki_do_reset
    j hki_done

hki_do_deal:
    jal start_new_round
    j hki_done

hki_do_hit:
    jal player_hit
    j hki_done

hki_do_stand:
    jal player_stand
    j hki_done

hki_do_reset:
    jal reset_session
    j hki_done

hki_done:
    lw $s0, 0($sp)
    lw $ra, 4($sp)
    addiu $sp, $sp, 8
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: flush_keyboard
# Purpose: Drains any buffered MMIO keystrokes to prevent stale actions.
# ------------------------------------------------------------------------------
flush_keyboard:
    li $t0, MMIO_RECV_CTRL
fk_loop:
    lw $t1, 0($t0)
    andi $t1, $t1, 1
    beqz $t1, fk_done
    lw $zero, 4($t0)       # read and discard
    j fk_loop
fk_done:
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: reset_session
# Purpose: Resets win/loss/push/round statistics and returns to opening screen.
# ------------------------------------------------------------------------------
reset_session:
    addiu $sp, $sp, -4
    sw $ra, 0($sp)

    sw $zero, stat_wins
    sw $zero, stat_losses
    sw $zero, stat_pushes
    sw $zero, stat_rounds
    sw $zero, result_code
    sw $zero, player_card_count
    sw $zero, dealer_card_count
    sw $zero, player_score
    sw $zero, dealer_score

    li $t0, STATE_OPENING
    sw $t0, game_state

    jal flush_keyboard
    jal render_screen

    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: start_new_round
# Purpose: Shuffles deck, deals initial alternating hands, evaluates blackjacks.
# ------------------------------------------------------------------------------
start_new_round:
    addiu $sp, $sp, -4
    sw $ra, 0($sp)

    # Guard: only allow new round on opening or round over
    lw $t0, game_state
    beq $t0, STATE_OPENING, snr_proceed
    beq $t0, STATE_ROUND_OVER, snr_proceed
    j snr_early_exit
snr_proceed:

    # Increment round counter
    lw $t0, stat_rounds
    addiu $t0, $t0, 1
    sw $t0, stat_rounds

    # Reset round variables
    sw $zero, player_card_count
    sw $zero, dealer_card_count
    li $t0, 1
    sw $t0, dealer_hole_hidden
    sw $zero, result_code

    # Shuffle fresh 52-card deck
    jal deck_init_and_shuffle

    # Deal alternating 4 cards: Player, Dealer, Player, Dealer
    # 1. Player Card 1
    jal deal_card_player
    # 2. Dealer Card 1 (Upcard)
    jal deal_card_dealer
    # 3. Player Card 2
    jal deal_card_player
    # 4. Dealer Card 2 (Hole card, hidden)
    jal deal_card_dealer

    # Evaluate initial hands
    la $a0, player_hand
    lw $a1, player_card_count
    jal eval_hand
    sw $v0, player_score

    la $a0, dealer_hand
    lw $a1, dealer_card_count
    jal eval_hand
    sw $v0, dealer_score

    # Check for natural blackjacks (exactly 2 cards totaling 21)
    lw $t0, player_score
    li $t1, 21
    seq $t2, $t0, $t1      # t2 = 1 if player has blackjack

    lw $t0, dealer_score
    seq $t3, $t0, $t1      # t3 = 1 if dealer has blackjack

    # Check simultaneous blackjacks
    and $t4, $t2, $t3
    beqz $t4, check_only_player_bj

    # Both have natural blackjack: PUSH
    sw $zero, dealer_hole_hidden   # reveal dealer hole card
    li $t0, RES_PUSH_BJ
    sw $t0, result_code
    lw $t5, stat_pushes
    addiu $t5, $t5, 1
    sw $t5, stat_pushes
    li $t0, STATE_ROUND_OVER
    sw $t0, game_state
    j snr_finish

check_only_player_bj:
    beqz $t2, check_only_dealer_bj
    # Player natural blackjack: WIN
    sw $zero, dealer_hole_hidden
    li $t0, RES_PLAYER_BJ
    sw $t0, result_code
    lw $t5, stat_wins
    addiu $t5, $t5, 1
    sw $t5, stat_wins
    li $t0, STATE_ROUND_OVER
    sw $t0, game_state
    j snr_finish

check_only_dealer_bj:
    beqz $t3, snr_player_turn
    # Dealer natural blackjack: LOSS
    sw $zero, dealer_hole_hidden
    li $t0, RES_DEALER_BJ
    sw $t0, result_code
    lw $t5, stat_losses
    addiu $t5, $t5, 1
    sw $t5, stat_losses
    li $t0, STATE_ROUND_OVER
    sw $t0, game_state
    j snr_finish

snr_player_turn:
    # No blackjacks: transition to Player's turn
    li $t0, STATE_PLAYER_TURN
    sw $t0, game_state

snr_finish:
    jal flush_keyboard
    jal render_screen

snr_early_exit:
    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: deal_card_player
# Purpose: Draws next card from deck and adds to player hand.
# ------------------------------------------------------------------------------
deal_card_player:
    la $t0, deck
    lw $t1, deck_index
    sll $t2, $t1, 2
    addu $t2, $t0, $t2
    lw $t3, 0($t2)         # card ID
    addiu $t1, $t1, 1
    sw $t1, deck_index

    la $t4, player_hand
    lw $t5, player_card_count
    sll $t6, $t5, 2
    addu $t6, $t4, $t6
    sw $t3, 0($t6)
    addiu $t5, $t5, 1
    sw $t5, player_card_count
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: deal_card_dealer
# Purpose: Draws next card from deck and adds to dealer hand.
# ------------------------------------------------------------------------------
deal_card_dealer:
    la $t0, deck
    lw $t1, deck_index
    sll $t2, $t1, 2
    addu $t2, $t0, $t2
    lw $t3, 0($t2)         # card ID
    addiu $t1, $t1, 1
    sw $t1, deck_index

    la $t4, dealer_hand
    lw $t5, dealer_card_count
    sll $t6, $t5, 2
    addu $t6, $t4, $t6
    sw $t3, 0($t6)
    addiu $t5, $t5, 1
    sw $t5, dealer_card_count
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: player_hit
# Purpose: Deals card to player. Handles bust (>21) or auto-stand (=21).
# ------------------------------------------------------------------------------
player_hit:
    addiu $sp, $sp, -4
    sw $ra, 0($sp)

    # Guard: only allow hit during player turn
    lw $t0, game_state
    bne $t0, STATE_PLAYER_TURN, ph_done

    # Deal 1 card to player
    jal deal_card_player

    # Evaluate new player total
    la $a0, player_hand
    lw $a1, player_card_count
    jal eval_hand
    sw $v0, player_score

    # Check for bust (> 21)
    ble $v0, 21, ph_check_21

    # Player BUST! Immediately end round as a loss
    sw $zero, dealer_hole_hidden   # reveal dealer hole card
    li $t0, RES_PLAYER_BUST
    sw $t0, result_code
    lw $t1, stat_losses
    addiu $t1, $t1, 1
    sw $t1, stat_losses
    li $t0, STATE_ROUND_OVER
    sw $t0, game_state
    jal flush_keyboard
    jal render_screen
    j ph_done

ph_check_21:
    bne $v0, 21, ph_continue
    # Player reached 21: automatically ends player turn
    jal flush_keyboard
    jal player_stand
    j ph_done

ph_continue:
    # Under 21: hand still active
    jal flush_keyboard
    jal render_screen

ph_done:
    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: player_stand
# Purpose: Ends player's turn, reveals dealer hole card, and starts dealer AI.
# ------------------------------------------------------------------------------
player_stand:
    addiu $sp, $sp, -4
    sw $ra, 0($sp)

    # Guard: only allow stand during player turn
    lw $t0, game_state
    bne $t0, STATE_PLAYER_TURN, ps_done

    # Transition to dealer turn & reveal hole card
    li $t0, STATE_DEALER_TURN
    sw $t0, game_state
    sw $zero, dealer_hole_hidden

    jal render_screen
    jal dealer_turn_play

ps_done:
    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: dealer_turn_play
# Purpose: Automated dealer logic. Hits below 17, stands on all 17s (including
#          soft 17). Renders each card with pacing, then resolves winner.
# ------------------------------------------------------------------------------
dealer_turn_play:
    addiu $sp, $sp, -4
    sw $ra, 0($sp)

dtp_loop:
    # Evaluate dealer total
    la $a0, dealer_hand
    lw $a1, dealer_card_count
    jal eval_hand
    sw $v0, dealer_score

    # Check if dealer must hit: total < 17
    # (If total is 17 or more, including soft 17, dealer stands)
    bge $v0, 17, dtp_resolve

    # Pacing delay so player sees dealer hit (350 ms)
    li $v0, 32
    li $a0, 350
    syscall

    # Deal card to dealer
    jal deal_card_dealer

    # Redraw screen with newly drawn card
    jal render_screen
    j dtp_loop

dtp_resolve:
    # Brief pause before showing final result banner (250 ms)
    li $v0, 32
    li $a0, 250
    syscall

    # Compare hands and determine outcome
    lw $t0, player_score
    lw $t1, dealer_score

    # 1. Did dealer bust (> 21)?
    ble $t1, 21, dtp_compare
    # Dealer Bust: Player Wins!
    li $t2, RES_DEALER_BUST
    sw $t2, result_code
    lw $t3, stat_wins
    addiu $t3, $t3, 1
    sw $t3, stat_wins
    j dtp_finish

dtp_compare:
    # 2. Player score > Dealer score?
    ble $t0, $t1, dtp_check_dealer_higher
    # Player Wins!
    li $t2, RES_PLAYER_WIN
    sw $t2, result_code
    lw $t3, stat_wins
    addiu $t3, $t3, 1
    sw $t3, stat_wins
    j dtp_finish

dtp_check_dealer_higher:
    # 3. Dealer score > Player score?
    ble $t1, $t0, dtp_check_push
    # Dealer Wins!
    li $t2, RES_DEALER_WIN
    sw $t2, result_code
    lw $t3, stat_losses
    addiu $t3, $t3, 1
    sw $t3, stat_losses
    j dtp_finish

dtp_check_push:
    # 4. Equal score: Push!
    li $t2, RES_PUSH
    sw $t2, result_code
    lw $t3, stat_pushes
    addiu $t3, $t3, 1
    sw $t3, stat_pushes

dtp_finish:
    li $t0, STATE_ROUND_OVER
    sw $t0, game_state

    jal flush_keyboard
    jal render_screen

    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: eval_hand
# Inputs:  $a0 = address of hand card array (words)
#          $a1 = number of cards
# Outputs: $v0 = evaluated total score
#          $v1 = is_soft flag (1 if an ace is currently counted as 11, else 0)
# Purpose: Calculates Blackjack hand total with complete multi-ace handling.
# ------------------------------------------------------------------------------
eval_hand:
    move $t0, $a0          # ptr
    move $t1, $a1          # count
    li $t2, 0              # sum
    li $t3, 0              # ace_count
    li $t4, 13             # divisor for rank = card % 13

eh_loop:
    blez $t1, eh_adjust
    lw $t5, 0($t0)         # card ID (0..51)
    addiu $t0, $t0, 4
    addiu $t1, $t1, -1

    # rank = card_id % 13
    divu $t5, $t4
    mfhi $t6               # rank: 0=Ace, 1=2 .. 8=9, 9=10, 10=J, 11=Q, 12=K

    # Check for Ace (rank == 0)
    bnez $t6, eh_check_face
    addiu $t3, $t3, 1      # ace_count++
    addiu $t2, $t2, 11     # initially count as 11
    j eh_loop

eh_check_face:
    li $t7, 9
    blt $t6, $t7, eh_pip
    # Rank 9..12 (10, J, Q, K) -> value 10
    addiu $t2, $t2, 10
    j eh_loop

eh_pip:
    # Rank 1..8 (cards 2..9) -> value rank + 1
    addiu $t6, $t6, 1
    addu $t2, $t2, $t6
    j eh_loop

eh_adjust:
    # If sum > 21 and we have aces counted as 11, reduce by 10 per ace
    ble $t2, 21, eh_done
    blez $t3, eh_done
    addiu $t2, $t2, -10
    addiu $t3, $t3, -1
    j eh_adjust

eh_done:
    move $v0, $t2          # total score
    sgt $v1, $t3, $zero    # 1 if at least one ace remains 11
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: deck_init_and_shuffle
# Purpose: Initializes deck with 0..51 and performs Fisher-Yates shuffle.
# ------------------------------------------------------------------------------
deck_init_and_shuffle:
    addiu $sp, $sp, -12
    sw $ra, 8($sp)
    sw $s0, 4($sp)
    sw $s1, 0($sp)

    # 1. Fill deck array with 0..51
    la $t0, deck
    li $t1, 0
dis_init_loop:
    sw $t1, 0($t0)
    addiu $t0, $t0, 4
    addiu $t1, $t1, 1
    blt $t1, 52, dis_init_loop

    # 2. Fisher-Yates shuffle: for i = 51 down to 1
    li $s0, 51
dis_shuffle_loop:
    blez $s0, dis_done

    # Random j in [0, i] (syscall 42 with bound i + 1)
    li $v0, 42
    li $a0, 0
    addiu $a1, $s0, 1
    syscall
    move $s1, $a0          # s1 = j (0..i)

    # Swap deck[i] and deck[j]
    la $t0, deck
    sll $t2, $s0, 2
    addu $t2, $t0, $t2     # &deck[i]
    lw $t3, 0($t2)         # deck[i]

    sll $t4, $s1, 2
    addu $t4, $t0, $t4     # &deck[j]
    lw $t5, 0($t4)         # deck[j]

    sw $t5, 0($t2)         # deck[i] = deck[j]
    sw $t3, 0($t4)         # deck[j] = deck[i]

    addiu $s0, $s0, -1
    j dis_shuffle_loop

dis_done:
    sw $zero, deck_index   # reset deck pointer to 0

    lw $s1, 0($sp)
    lw $s0, 4($sp)
    lw $ra, 8($sp)
    addiu $sp, $sp, 12
    jr $ra

# ==============================================================================
# SCREEN RENDERING ROUTINES
# ==============================================================================

# ------------------------------------------------------------------------------
# ROUTINE: render_screen
# Purpose: Complete frame redrawing according to current game state and scores.
# ------------------------------------------------------------------------------
render_screen:
    addiu $sp, $sp, -4
    sw $ra, 0($sp)

    jal draw_table_background
    jal draw_left_sidebar
    jal draw_dealer_hand
    jal draw_middle_banner
    jal draw_player_hand
    jal draw_control_strip

    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_table_background
# Purpose: Clears screen with deep teal felt and draws stitched perimeter border.
# ------------------------------------------------------------------------------
draw_table_background:
    addiu $sp, $sp, -4
    sw $ra, 0($sp)

    # Clear 256x128 framebuffer to felt color
    move $a0, $zero
    move $a1, $zero
    li $a2, SCREEN_WIDTH
    li $a3, SCREEN_HEIGHT
    addiu $sp, $sp, -4
    li $t0, COLOR_FELT_BG
    sw $t0, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Outer felt stitching border (2px from edge)
    li $a0, 2
    li $a1, 2
    li $a2, 252
    li $a3, 124
    addiu $sp, $sp, -4
    li $t0, COLOR_FELT_STITCH
    sw $t0, 0($sp)
    jal draw_rect_outline
    addiu $sp, $sp, 4

    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_left_sidebar
# Purpose: Renders left charcoal container with Jimbo portrait and session stats.
# ------------------------------------------------------------------------------
draw_left_sidebar:
    addiu $sp, $sp, -4
    sw $ra, 0($sp)

    # Main sidebar panel (X: 5, Y: 5, W: 54, H: 108)
    li $a0, 5
    li $a1, 5
    li $a2, 54
    li $a3, 108
    addiu $sp, $sp, -12
    li $t0, COLOR_PANEL_BG
    sw $t0, 0($sp)
    li $t0, COLOR_PANEL_BORDER
    sw $t0, 4($sp)
    li $t0, COLOR_PANEL_SHADOW
    sw $t0, 8($sp)
    jal draw_panel_with_shadow
    addiu $sp, $sp, 12

    # Gold frame around portrait (X: 18, Y: 7, W: 26, H: 26)
    li $a0, 18
    li $a1, 7
    li $a2, 26
    li $a3, 26
    addiu $sp, $sp, -4
    li $t0, COLOR_GOLD
    sw $t0, 0($sp)
    jal draw_rect_outline
    addiu $sp, $sp, 4

    # Draw 24x24 dealer sprite at (19, 8)
    li $a0, 19
    li $a1, 8
    li $a2, 24
    li $a3, 24
    addiu $sp, $sp, -8
    la $t0, dealer_sprite
    sw $t0, 0($sp)
    la $t0, portrait_palette
    sw $t0, 4($sp)
    jal draw_sprite_indexed
    addiu $sp, $sp, 8

    # Dealer name badge pill (X: 15, Y: 35, W: 32, H: 7)
    li $a0, 15
    li $a1, 35
    li $a2, 32
    li $a3, 7
    addiu $sp, $sp, -4
    li $t0, COLOR_PANEL_BORDER
    sw $t0, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Text "DEALER" inside badge
    li $a0, 19
    li $a1, 36
    la $a2, str_dealer_lbl
    li $a3, COLOR_CYAN
    jal draw_string_3x5

    # Horizontal divider line at Y: 44
    li $a0, 9
    li $a1, 44
    li $a2, 46
    li $a3, 1
    addiu $sp, $sp, -4
    li $t0, COLOR_PANEL_BORDER
    sw $t0, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Stats Section Title "* STATS *"
    li $a0, 14
    li $a1, 47
    la $a2, str_stats_title
    li $a3, COLOR_GOLD
    jal draw_string_3x5

    # Wins Label & Count
    li $a0, 9
    li $a1, 57
    la $a2, str_wins_lbl
    li $a3, COLOR_CYAN
    jal draw_string_3x5

    li $a0, 33
    li $a1, 57
    lw $a2, stat_wins
    li $a3, COLOR_WHITE
    jal draw_int_3x5

    # Loss Label & Count
    li $a0, 9
    li $a1, 69
    la $a2, str_loss_lbl
    li $a3, COLOR_CORAL
    jal draw_string_3x5

    li $a0, 33
    li $a1, 69
    lw $a2, stat_losses
    li $a3, COLOR_WHITE
    jal draw_int_3x5

    # Push Label & Count
    li $a0, 9
    li $a1, 81
    la $a2, str_push_lbl
    li $a3, COLOR_PURPLE
    jal draw_string_3x5

    li $a0, 33
    li $a1, 81
    lw $a2, stat_pushes
    li $a3, COLOR_WHITE
    jal draw_int_3x5

    # Rounds Label & Count
    li $a0, 9
    li $a1, 93
    la $a2, str_rnds_lbl
    li $a3, COLOR_CREAM
    jal draw_string_3x5

    li $a0, 33
    li $a1, 93
    lw $a2, stat_rounds
    li $a3, COLOR_WHITE
    jal draw_int_3x5

    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_dealer_hand
# Purpose: Renders dealer title, score badge, and cards (face-up or patterned back).
# ------------------------------------------------------------------------------
draw_dealer_hand:
    addiu $sp, $sp, -20
    sw $ra, 16($sp)
    sw $s0, 12($sp)
    sw $s1, 8($sp)
    sw $s2, 4($sp)
    sw $s3, 0($sp)

    # Dealer section header label "DEALER HAND"
    li $a0, 65
    li $a1, 6
    la $a2, str_dealer_hand
    li $a3, COLOR_CREAM
    jal draw_string_3x5

    # Score badge pill (X: 136, Y: 5, W: 52, H: 9)
    li $a0, 136
    li $a1, 5
    li $a2, 52
    li $a3, 9
    addiu $sp, $sp, -12
    li $t0, COLOR_PANEL_BG
    sw $t0, 0($sp)
    li $t0, COLOR_PANEL_BORDER
    sw $t0, 4($sp)
    li $t0, COLOR_PANEL_SHADOW
    sw $t0, 8($sp)
    jal draw_panel_with_shadow
    addiu $sp, $sp, 12

    # Choose badge text
    lw $t0, game_state
    beq $t0, STATE_OPENING, ddh_score_dash

    lw $t1, dealer_hole_hidden
    bnez $t1, ddh_score_hide

    # Dealer score revealed!
    lw $t2, dealer_score
    ble $t2, 21, ddh_check_bj

    # Bust score
    li $a0, 144
    li $a1, 7
    la $a2, str_score_bust
    li $a3, COLOR_CORAL
    jal draw_string_3x5
    li $a0, 166
    li $a1, 7
    lw $a2, dealer_score
    li $a3, COLOR_CORAL
    jal draw_int_3x5
    j ddh_draw_cards

ddh_check_bj:
    lw $t3, dealer_card_count
    bne $t3, 2, ddh_score_total
    bne $t2, 21, ddh_score_total

    # Natural Blackjack
    li $a0, 152
    li $a1, 7
    la $a2, str_score_bj
    li $a3, COLOR_GOLD
    jal draw_string_3x5
    j ddh_draw_cards

ddh_score_total:
    li $a0, 140
    li $a1, 7
    la $a2, str_score_tot
    li $a3, COLOR_CYAN
    jal draw_string_3x5
    li $a0, 168
    li $a1, 7
    lw $a2, dealer_score
    li $a3, COLOR_CYAN
    jal draw_int_3x5
    j ddh_draw_cards

ddh_score_dash:
    li $a0, 154
    li $a1, 7
    la $a2, str_score_dash
    li $a3, COLOR_TEXT_DIM
    jal draw_string_3x5
    j ddh_draw_cards

ddh_score_hide:
    li $a0, 154
    li $a1, 7
    la $a2, str_score_hide
    li $a3, COLOR_TEXT_DIM
    jal draw_string_3x5

ddh_draw_cards:
    lw $s0, dealer_card_count
    bnez $s0, ddh_render_active_cards

    # In opening state, draw 2 dashed card placeholders
    li $a0, 65
    li $a1, 17
    li $a2, 22
    li $a3, 32
    addiu $sp, $sp, -4
    li $t0, COLOR_FELT_STITCH
    sw $t0, 0($sp)
    jal draw_rect_outline
    addiu $sp, $sp, 4

    li $a0, 89
    li $a1, 17
    li $a2, 22
    li $a3, 32
    addiu $sp, $sp, -4
    li $t0, COLOR_FELT_STITCH
    sw $t0, 0($sp)
    jal draw_rect_outline
    addiu $sp, $sp, 4
    j ddh_exit

ddh_render_active_cards:
    # Adaptive horizontal spacing based on count
    li $s1, 20             # delta_x default for <= 5 cards
    ble $s0, 5, ddh_cards_loop_init
    li $s1, 17
    beq $s0, 6, ddh_cards_loop_init
    li $s1, 15
    beq $s0, 7, ddh_cards_loop_init
    li $s1, 13             # delta_x for 8+ cards

ddh_cards_loop_init:
    li $s2, 0              # card index i = 0

ddh_cards_loop:
    bge $s2, $s0, ddh_exit

    # X = 65 + i * delta_x
    mul $t0, $s2, $s1
    addiu $s3, $t0, 65     # card X

    # Card ID
    la $t1, dealer_hand
    sll $t2, $s2, 2
    addu $t2, $t1, $t2
    lw $a2, 0($t2)         # a2 = card_id

    # Check if face-down (card index 1 when dealer_hole_hidden == 1)
    li $a3, 0              # face-up by default
    bne $s2, 1, ddh_call_draw_card
    lw $t3, dealer_hole_hidden
    beqz $t3, ddh_call_draw_card
    li $a3, 1              # face-down!

ddh_call_draw_card:
    move $a0, $s3
    li $a1, 17
    jal draw_card

    addiu $s2, $s2, 1
    j ddh_cards_loop

ddh_exit:
    lw $s3, 0($sp)
    lw $s2, 4($sp)
    lw $s1, 8($sp)
    lw $s0, 12($sp)
    lw $ra, 16($sp)
    addiu $sp, $sp, 20
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_middle_banner
# Purpose: Renders prominent middle status / outcome message banner.
# ------------------------------------------------------------------------------
draw_middle_banner:
    addiu $sp, $sp, -8
    sw $ra, 4($sp)
    sw $s0, 0($sp)

    # Banner pill (X: 64, Y: 51, W: 186, H: 15)
    li $a0, 64
    li $a1, 51
    li $a2, 186
    li $a3, 15
    addiu $sp, $sp, -12
    li $t0, COLOR_PANEL_BG
    sw $t0, 0($sp)
    li $t0, COLOR_PANEL_BORDER
    sw $t0, 4($sp)
    li $t0, COLOR_PANEL_SHADOW
    sw $t0, 8($sp)
    jal draw_panel_with_shadow
    addiu $sp, $sp, 12

    # Select message string and color based on state
    lw $t0, game_state
    beq $t0, STATE_OPENING, dmb_opening
    beq $t0, STATE_PLAYER_TURN, dmb_player_turn
    beq $t0, STATE_DEALER_TURN, dmb_dealer_turn

    # In STATE_ROUND_OVER, check result_code
    lw $t1, result_code
    beq $t1, RES_PLAYER_BJ, dmb_res_pj_bj
    beq $t1, RES_DEALER_BJ, dmb_res_dl_bj
    beq $t1, RES_PUSH_BJ, dmb_res_ps_bj
    beq $t1, RES_PLAYER_BUST, dmb_res_pj_bust
    beq $t1, RES_DEALER_BUST, dmb_res_dl_bust
    beq $t1, RES_PLAYER_WIN, dmb_res_pj_win
    beq $t1, RES_DEALER_WIN, dmb_res_dl_win
    beq $t1, RES_PUSH, dmb_res_push

    # Fallback
    la $a2, str_msg_welcome
    li $a3, COLOR_GOLD
    j dmb_center_and_draw

dmb_opening:
    la $a2, str_msg_welcome
    li $a3, COLOR_GOLD
    j dmb_center_and_draw

dmb_player_turn:
    la $a2, str_msg_player
    li $a3, COLOR_CYAN
    j dmb_center_and_draw

dmb_dealer_turn:
    la $a2, str_msg_dealer
    li $a3, COLOR_GOLD
    j dmb_center_and_draw

dmb_res_pj_bj:
    la $a2, str_msg_pj_bj
    li $a3, COLOR_GOLD
    j dmb_center_and_draw

dmb_res_dl_bj:
    la $a2, str_msg_dl_bj
    li $a3, COLOR_CORAL
    j dmb_center_and_draw

dmb_res_ps_bj:
    la $a2, str_msg_ps_bj
    li $a3, COLOR_PURPLE
    j dmb_center_and_draw

dmb_res_pj_bust:
    la $a2, str_msg_pj_bust
    li $a3, COLOR_CORAL
    j dmb_center_and_draw

dmb_res_dl_bust:
    la $a2, str_msg_dl_bust
    li $a3, COLOR_CYAN
    j dmb_center_and_draw

dmb_res_pj_win:
    la $a2, str_msg_pj_win
    li $a3, COLOR_CYAN
    j dmb_center_and_draw

dmb_res_dl_win:
    la $a2, str_msg_dl_win
    li $a3, COLOR_CORAL
    j dmb_center_and_draw

dmb_res_push:
    la $a2, str_msg_push
    li $a3, COLOR_PURPLE

dmb_center_and_draw:
    # Save string pointer and color
    move $s0, $a2          # str
    move $s1, $a3          # color

    # Calculate centered X position: 64 + (186 - len * 4) / 2
    move $a0, $s0
    jal strlen
    sll $t0, $v0, 2        # text_width = len * 4
    li $t1, 186
    subu $t1, $t1, $t0     # 186 - text_width
    sra $t1, $t1, 1        # / 2
    addiu $a0, $t1, 64     # centered X

    li $a1, 56             # centered Y inside banner
    move $a2, $s0
    move $a3, $s1
    addiu $sp, $sp, -4
    li $t2, COLOR_PANEL_SHADOW
    sw $t2, 0($sp)
    jal draw_string_shadow
    addiu $sp, $sp, 4

    lw $s0, 0($sp)
    lw $ra, 4($sp)
    addiu $sp, $sp, 8
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_player_hand
# Purpose: Renders player title, score badge, and cards (all face-up).
# ------------------------------------------------------------------------------
draw_player_hand:
    addiu $sp, $sp, -20
    sw $ra, 16($sp)
    sw $s0, 12($sp)
    sw $s1, 8($sp)
    sw $s2, 4($sp)
    sw $s3, 0($sp)

    # Player section header label "PLAYER HAND"
    li $a0, 65
    li $a1, 70
    la $a2, str_player_hand
    li $a3, COLOR_CREAM
    jal draw_string_3x5

    # Score badge pill (X: 136, Y: 69, W: 52, H: 9)
    li $a0, 136
    li $a1, 69
    li $a2, 52
    li $a3, 9
    addiu $sp, $sp, -12
    li $t0, COLOR_PANEL_BG
    sw $t0, 0($sp)
    li $t0, COLOR_PANEL_BORDER
    sw $t0, 4($sp)
    li $t0, COLOR_PANEL_SHADOW
    sw $t0, 8($sp)
    jal draw_panel_with_shadow
    addiu $sp, $sp, 12

    # Choose badge text
    lw $t0, game_state
    beq $t0, STATE_OPENING, dph_score_dash

    lw $t2, player_score
    ble $t2, 21, dph_check_bj

    # Bust score
    li $a0, 144
    li $a1, 71
    la $a2, str_score_bust
    li $a3, COLOR_CORAL
    jal draw_string_3x5
    li $a0, 166
    li $a1, 71
    lw $a2, player_score
    li $a3, COLOR_CORAL
    jal draw_int_3x5
    j dph_draw_cards

dph_check_bj:
    lw $t3, player_card_count
    bne $t3, 2, dph_score_total
    bne $t2, 21, dph_score_total

    # Natural Blackjack
    li $a0, 152
    li $a1, 71
    la $a2, str_score_bj
    li $a3, COLOR_GOLD
    jal draw_string_3x5
    j dph_draw_cards

dph_score_total:
    li $a0, 140
    li $a1, 71
    la $a2, str_score_tot
    li $a3, COLOR_CYAN
    jal draw_string_3x5
    li $a0, 168
    li $a1, 71
    lw $a2, player_score
    li $a3, COLOR_CYAN
    jal draw_int_3x5
    j dph_draw_cards

dph_score_dash:
    li $a0, 154
    li $a1, 71
    la $a2, str_score_dash
    li $a3, COLOR_TEXT_DIM
    jal draw_string_3x5

dph_draw_cards:
    lw $s0, player_card_count
    bnez $s0, dph_render_active_cards

    # In opening state, draw 2 dashed card placeholders
    li $a0, 65
    li $a1, 81
    li $a2, 22
    li $a3, 32
    addiu $sp, $sp, -4
    li $t0, COLOR_FELT_STITCH
    sw $t0, 0($sp)
    jal draw_rect_outline
    addiu $sp, $sp, 4

    li $a0, 89
    li $a1, 81
    li $a2, 22
    li $a3, 32
    addiu $sp, $sp, -4
    li $t0, COLOR_FELT_STITCH
    sw $t0, 0($sp)
    jal draw_rect_outline
    addiu $sp, $sp, 4
    j dph_exit

dph_render_active_cards:
    # Adaptive horizontal spacing based on count
    li $s1, 20             # delta_x default for <= 5 cards
    ble $s0, 5, dph_cards_loop_init
    li $s1, 17
    beq $s0, 6, dph_cards_loop_init
    li $s1, 15
    beq $s0, 7, dph_cards_loop_init
    li $s1, 13             # delta_x for 8+ cards

dph_cards_loop_init:
    li $s2, 0              # card index i = 0

dph_cards_loop:
    bge $s2, $s0, dph_exit

    # X = 65 + i * delta_x
    mul $t0, $s2, $s1
    addiu $s3, $t0, 65     # card X

    # Card ID
    la $t1, player_hand
    sll $t2, $s2, 2
    addu $t2, $t1, $t2
    lw $a2, 0($t2)         # a2 = card_id
    li $a3, 0              # player cards always face up

    move $a0, $s3
    li $a1, 81
    jal draw_card

    addiu $s2, $s2, 1
    j dph_cards_loop

dph_exit:
    lw $s3, 0($sp)
    lw $s2, 4($sp)
    lw $s1, 8($sp)
    lw $s0, 12($sp)
    lw $ra, 16($sp)
    addiu $sp, $sp, 20
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_control_strip
# Purpose: Renders persistent bottom control strip with color-highlighted
#          active buttons and dimmed unavailable actions.
# ------------------------------------------------------------------------------
draw_control_strip:
    addiu $sp, $sp, -8
    sw $ra, 4($sp)
    sw $s0, 0($sp)

    # Dark background bar (X: 0, Y: 115, W: 256, H: 13)
    move $a0, $zero
    li $a1, 115
    li $a2, SCREEN_WIDTH
    li $a3, 13
    addiu $sp, $sp, -4
    li $t0, 0x0013161C
    sw $t0, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Top border line at Y: 115
    move $a0, $zero
    li $a1, 115
    li $a2, SCREEN_WIDTH
    li $a3, 1
    addiu $sp, $sp, -4
    li $t0, COLOR_PANEL_BORDER
    sw $t0, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    lw $s0, game_state     # s0 = game_state (preserved across button calls)

    # 1. Button [N] DEAL (X: 5, Y: 117, W: 46, H: 9)
    # Active in STATE_OPENING and STATE_ROUND_OVER
    li $t1, 0
    beq $s0, STATE_OPENING, dcs_n_active
    beq $s0, STATE_ROUND_OVER, dcs_n_active
    j dcs_draw_n
dcs_n_active:
    li $t1, 1
dcs_draw_n:
    li $a0, 5
    li $a1, 117
    li $a2, 46
    li $a3, 9
    addiu $sp, $sp, -20
    la $t2, str_btn_deal
    sw $t2, 0($sp)
    sw $t1, 4($sp)
    li $t2, COLOR_GOLD
    sw $t2, 8($sp)
    li $t2, COLOR_GOLD_SHADOW
    sw $t2, 12($sp)
    li $t2, 0x001A1800     # dark text on gold button
    sw $t2, 16($sp)
    jal draw_ui_button
    addiu $sp, $sp, 20

    # 2. Button [H] HIT (X: 55, Y: 117, W: 40, H: 9)
    # Active only in STATE_PLAYER_TURN
    li $t1, 0
    bne $s0, STATE_PLAYER_TURN, dcs_draw_h
    li $t1, 1
dcs_draw_h:
    li $a0, 55
    li $a1, 117
    li $a2, 40
    li $a3, 9
    addiu $sp, $sp, -20
    la $t2, str_btn_hit
    sw $t2, 0($sp)
    sw $t1, 4($sp)
    li $t2, COLOR_CORAL
    sw $t2, 8($sp)
    li $t2, COLOR_CORAL_SHADOW
    sw $t2, 12($sp)
    li $t2, COLOR_WHITE
    sw $t2, 16($sp)
    jal draw_ui_button
    addiu $sp, $sp, 20

    # 3. Button [S] STAND (X: 99, Y: 117, W: 48, H: 9)
    # Active only in STATE_PLAYER_TURN
    li $t1, 0
    bne $s0, STATE_PLAYER_TURN, dcs_draw_s
    li $t1, 1
dcs_draw_s:
    li $a0, 99
    li $a1, 117
    li $a2, 48
    li $a3, 9
    addiu $sp, $sp, -20
    la $t2, str_btn_stand
    sw $t2, 0($sp)
    sw $t1, 4($sp)
    li $t2, COLOR_CYAN
    sw $t2, 8($sp)
    li $t2, COLOR_CYAN_SHADOW
    sw $t2, 12($sp)
    li $t2, 0x00062020     # deep teal text on cyan button
    sw $t2, 16($sp)
    jal draw_ui_button
    addiu $sp, $sp, 20

    # 4. Button [R] RESET (X: 151, Y: 117, W: 48, H: 9)
    # Active in STATE_OPENING and STATE_ROUND_OVER
    li $t1, 0
    beq $s0, STATE_OPENING, dcs_r_active
    beq $s0, STATE_ROUND_OVER, dcs_r_active
    j dcs_draw_r
dcs_r_active:
    li $t1, 1
dcs_draw_r:
    li $a0, 151
    li $a1, 117
    li $a2, 48
    li $a3, 9
    addiu $sp, $sp, -20
    la $t2, str_btn_reset
    sw $t2, 0($sp)
    sw $t1, 4($sp)
    li $t2, COLOR_PURPLE
    sw $t2, 8($sp)
    li $t2, COLOR_PURPLE_SHADOW
    sw $t2, 12($sp)
    li $t2, COLOR_WHITE
    sw $t2, 16($sp)
    jal draw_ui_button
    addiu $sp, $sp, 20

    # 5. Button [Q] QUIT (X: 203, Y: 117, W: 48, H: 9)
    # Always active
    li $a0, 203
    li $a1, 117
    li $a2, 48
    li $a3, 9
    addiu $sp, $sp, -20
    la $t2, str_btn_quit
    sw $t2, 0($sp)
    li $t2, 1
    sw $t2, 4($sp)
    li $t2, 0x003A4252     # slate gray
    sw $t2, 8($sp)
    li $t2, 0x001E222A     # slate shadow
    sw $t2, 12($sp)
    li $t2, COLOR_CREAM
    sw $t2, 16($sp)
    jal draw_ui_button
    addiu $sp, $sp, 20

    lw $s0, 0($sp)
    lw $ra, 4($sp)
    addiu $sp, $sp, 8
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_ui_button
# Inputs:  $a0 = x, $a1 = y, $a2 = w, $a3 = h
# Stack:   0($sp)  = str_ptr
#          4($sp)  = is_active (1 = active, 0 = disabled)
#          8($sp)  = active_bg_color
#          12($sp) = active_shadow_color
#          16($sp) = active_text_color
# Purpose: Renders 3D beveled button with centered label.
# ------------------------------------------------------------------------------
draw_ui_button:
    addiu $sp, $sp, -36
    sw $ra, 32($sp)
    sw $s0, 28($sp)
    sw $s1, 24($sp)
    sw $s2, 20($sp)
    sw $s3, 16($sp)
    sw $s4, 12($sp)
    sw $s5, 8($sp)
    sw $s6, 4($sp)
    sw $s7, 0($sp)

    move $s0, $a0          # x
    move $s1, $a1          # y
    move $s2, $a2          # w
    move $s3, $a3          # h

    lw $s4, 36($sp)        # str_ptr
    lw $s5, 40($sp)        # is_active
    lw $s6, 44($sp)        # active_bg
    lw $s7, 48($sp)        # active_shadow
    lw $t8, 52($sp)        # active_text

    beqz $s5, dub_inactive

    # Active button: 1px drop shadow
    addiu $a0, $s0, 1
    addiu $a1, $s1, 1
    move $a2, $s2
    move $a3, $s3
    addiu $sp, $sp, -4
    sw $s7, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Button body
    move $a0, $s0
    move $a1, $s1
    move $a2, $s2
    move $a3, $s3
    addiu $sp, $sp, -4
    sw $s6, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Calculate centered text position: s0 + (s2 - len * 4) / 2
    move $a0, $s4
    jal strlen
    sll $t0, $v0, 2        # len * 4
    subu $t1, $s2, $t0     # w - text_width
    sra $t1, $t1, 1
    addu $a0, $s0, $t1     # centered X
    addiu $a1, $s1, 2      # centered Y
    move $a2, $s4
    move $a3, $t8          # active text color
    jal draw_string_3x5
    j dub_done

dub_inactive:
    # Inactive button: muted slate flat box
    move $a0, $s0
    move $a1, $s1
    move $a2, $s2
    move $a3, $s3
    addiu $sp, $sp, -4
    li $t0, COLOR_BTN_INACTIVE_BG
    sw $t0, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Border outline
    move $a0, $s0
    move $a1, $s1
    move $a2, $s2
    move $a3, $s3
    addiu $sp, $sp, -4
    li $t0, COLOR_BTN_INACTIVE_BD
    sw $t0, 0($sp)
    jal draw_rect_outline
    addiu $sp, $sp, 4

    # Muted centered text
    move $a0, $s4
    jal strlen
    sll $t0, $v0, 2
    subu $t1, $s2, $t0
    sra $t1, $t1, 1
    addu $a0, $s0, $t1
    addiu $a1, $s1, 2
    move $a2, $s4
    li $a3, COLOR_TEXT_DIM
    jal draw_string_3x5

dub_done:
    lw $s7, 0($sp)
    lw $s6, 4($sp)
    lw $s5, 8($sp)
    lw $s4, 12($sp)
    lw $s3, 16($sp)
    lw $s2, 20($sp)
    lw $s1, 24($sp)
    lw $s0, 28($sp)
    lw $ra, 32($sp)
    addiu $sp, $sp, 36
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_card
# Inputs:  $a0 = x, $a1 = y, $a2 = card_id (0..51), $a3 = is_face_down (0 or 1)
# Purpose: Renders 22x32 playing card with drop shadow, outer border, and either
#          ornate patterned Balatro back or warm cream face with suits & ranks.
# ------------------------------------------------------------------------------
draw_card:
    addiu $sp, $sp, -28
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)
    sw $s5, 0($sp)

    move $s0, $a0          # x
    move $s1, $a1          # y
    move $s2, $a2          # card_id
    move $s3, $a3          # is_face_down

    # 1. Drop shadow: right edge (x+22, y+2 .. y+32)
    addiu $a0, $s0, 22
    addiu $a1, $s1, 2
    li $a2, 1
    li $a3, 31
    addiu $sp, $sp, -4
    li $t0, COLOR_CARD_SHADOW
    sw $t0, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Drop shadow: bottom edge (x+2 .. x+22, y+32)
    addiu $a0, $s0, 2
    addiu $a1, $s1, 32
    li $a2, 21
    li $a3, 1
    addiu $sp, $sp, -4
    li $t0, COLOR_CARD_SHADOW
    sw $t0, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # 2. Outer dark border (22 x 32)
    move $a0, $s0
    move $a1, $s1
    li $a2, 22
    li $a3, 32
    addiu $sp, $sp, -4
    li $t0, COLOR_CARD_BORDER
    sw $t0, 0($sp)
    jal draw_rect_outline
    addiu $sp, $sp, 4

    # 3. Branch: Face Down vs Face Up
    bnez $s3, dc_draw_back

    # ==========================
    # FACE UP CARD RENDERING
    # ==========================
    # Warm vintage cream card face (20 x 30)
    addiu $a0, $s0, 1
    addiu $a1, $s1, 1
    li $a2, 20
    li $a3, 30
    addiu $sp, $sp, -4
    li $t0, COLOR_CARD_FACE
    sw $t0, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Determine rank (0..12) and suit (0..3)
    li $t0, 13
    divu $s2, $t0
    mfhi $s4               # s4 = rank (0..12)
    mflo $s5               # s5 = suit (0=Spade, 1=Heart, 2=Club, 3=Diamond)

    # Suit color: Red for Heart(1)/Diamond(3); Charcoal for Spade(0)/Club(2)
    li $t1, COLOR_SUIT_BLACK
    beq $s5, 1, dc_set_red
    beq $s5, 3, dc_set_red
    j dc_got_suit_color
dc_set_red:
    li $t1, COLOR_SUIT_RED
dc_got_suit_color:
    move $s3, $t1          # s3 = suit color

    # Draw Top-Left Rank
    bne $s4, 9, dc_single_rank_tl
    # Rank 10: draw '1' and '0'
    addiu $a0, $s0, 2
    addiu $a1, $s1, 2
    li $a2, '1'
    move $a3, $s3
    jal draw_char_3x5

    addiu $a0, $s0, 6
    addiu $a1, $s1, 2
    li $a2, '0'
    move $a3, $s3
    jal draw_char_3x5
    j dc_top_left_suit

dc_single_rank_tl:
    la $t2, rank_chars
    addu $t2, $t2, $s4
    lbu $a2, 0($t2)        # rank character
    addiu $a0, $s0, 2
    addiu $a1, $s1, 2
    move $a3, $s3
    jal draw_char_3x5

dc_top_left_suit:
    # 5x5 Suit icon at (x+2, y+8)
    addiu $a0, $s0, 2
    addiu $a1, $s1, 8
    move $a2, $s5          # suit
    move $a3, $s3          # color
    jal draw_suit_5x5

    # Center Illustration:
    # If court card (rank >= 10: J, Q, K), draw 7x7 Gold Crown + small suit
    blt $s4, 10, dc_center_pip

    # Royal Crown at (x+7, y+12)
    addiu $a0, $s0, 7
    addiu $a1, $s1, 12
    li $a2, 4              # 4 = Crown in icon_7x7
    li $a3, COLOR_GOLD
    jal draw_icon_7x7

    # Center suit at (x+8, y+20)
    addiu $a0, $s0, 8
    addiu $a1, $s1, 20
    move $a2, $s5
    move $a3, $s3
    jal draw_suit_5x5
    j dc_bottom_right_rank

dc_center_pip:
    # Centered 7x7 suit icon at (x+7, y+13)
    addiu $a0, $s0, 7
    addiu $a1, $s1, 13
    move $a2, $s5
    move $a3, $s3
    jal draw_icon_7x7

dc_bottom_right_rank:
    # Draw Bottom-Right Rank
    bne $s4, 9, dc_single_rank_br
    # Rank 10 at bottom right
    addiu $a0, $s0, 13
    addiu $a1, $s1, 25
    li $a2, '1'
    move $a3, $s3
    jal draw_char_3x5

    addiu $a0, $s0, 17
    addiu $a1, $s1, 25
    li $a2, '0'
    move $a3, $s3
    jal draw_char_3x5
    j dc_card_done

dc_single_rank_br:
    la $t2, rank_chars
    addu $t2, $t2, $s4
    lbu $a2, 0($t2)
    addiu $a0, $s0, 17
    addiu $a1, $s1, 25
    move $a3, $s3
    jal draw_char_3x5
    j dc_card_done

    # ==========================
    # FACE DOWN CARD RENDERING
    # ==========================
dc_draw_back:
    # Outer margin of card back (20 x 30 in dark burgundy 0x0078181E)
    addiu $a0, $s0, 1
    addiu $a1, $s1, 1
    li $a2, 20
    li $a3, 30
    addiu $sp, $sp, -4
    li $t0, 0x0078181E
    sw $t0, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Inner decorative patterned grid (18 wide x 28 tall)
    # Loop over v from 0 to 27, u from 0 to 17
    li $s4, 0              # v = 0 (row)
dc_back_v_loop:
    bge $s4, 28, dc_card_done

    li $s5, 0              # u = 0 (col)
dc_back_u_loop:
    bge $s5, 18, dc_back_v_next

    # Calculate pixel screen coordinates
    addiu $a0, $s0, 2
    addu $a0, $a0, $s5     # px = x + 2 + u

    addiu $a1, $s1, 2
    addu $a1, $a1, $s4     # py = y + 2 + v

    # Center diamond emblem check:
    # du = abs(u - 8), dv = abs(v - 13)
    subiu $t0, $s5, 8
    bgez $t0, dc_du_pos
    negu $t0, $t0
dc_du_pos:

    subiu $t1, $s4, 13
    bgez $t1, dc_dv_pos
    negu $t1, $t1
dc_dv_pos:

    addu $t2, $t0, $t1     # sum_d = du + dv
    bgt $t2, 4, dc_back_pattern

    # Inside central seal!
    # Center cross / star is white
    beqz $t2, dc_star_white
    bnez $t0, dc_check_v_star
    ble $t1, 2, dc_star_white
dc_check_v_star:
    bnez $t1, dc_seal_blue
    ble $t0, 2, dc_star_white

dc_seal_blue:
    li $a2, COLOR_CARD_BACK_EMBL   # royal blue emblem
    jal draw_pixel
    j dc_back_u_next

dc_star_white:
    li $a2, COLOR_WHITE            # white star
    jal draw_pixel
    j dc_back_u_next

dc_back_pattern:
    # Diagonal crosshatch pattern:
    # if (u + v) % 4 == 0 or (u - v + 28) % 4 == 0 -> orange line
    addu $t3, $s5, $s4     # u + v
    andi $t3, $t3, 3
    beqz $t3, dc_pat_orange

    subu $t4, $s5, $s4
    addiu $t4, $t4, 28     # u - v + 28
    andi $t4, $t4, 3
    beqz $t4, dc_pat_orange

    # Coral red base
    li $a2, COLOR_CARD_BACK_BASE
    jal draw_pixel
    j dc_back_u_next

dc_pat_orange:
    li $a2, COLOR_CARD_BACK_LINE
    jal draw_pixel

dc_back_u_next:
    addiu $s5, $s5, 1
    j dc_back_u_loop

dc_back_v_next:
    addiu $s4, $s4, 1
    j dc_back_v_loop

dc_card_done:
    lw $s5, 0($sp)
    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addiu $sp, $sp, 28
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_suit_5x5
# Inputs:  $a0 = x, $a1 = y, $a2 = suit (0=Spade, 1=Heart, 2=Club, 3=Diamond)
#          $a3 = color
# Purpose: Renders 5x5 pixel suit icon from suit_5x5_data bitmap table.
# ------------------------------------------------------------------------------
draw_suit_5x5:
    addiu $sp, $sp, -28
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)

    move $s0, $a0          # x
    move $s1, $a1          # y
    move $s2, $a2          # suit
    move $s3, $a3          # color

    la $t0, suit_5x5_data
    mul $t1, $s2, 5
    addu $s4, $t0, $t1     # ptr to 5 bytes

    li $t2, 0              # row = 0
s5_row_loop:
    bge $t2, 5, s5_done
    lbu $t3, 0($s4)        # row bits (5 bits)
    addiu $s4, $s4, 1

    addu $a1, $s1, $t2     # screen Y
    move $a2, $s3          # color

    li $t5, 0              # bit col = 0..4
s5_col_loop:
    bge $t5, 5, s5_row_next
    li $t6, 4
    subu $t6, $t6, $t5     # shift = 4 - col
    srlv $t7, $t3, $t6
    andi $t7, $t7, 1
    beqz $t7, s5_col_next

    addu $a0, $s0, $t5     # screen X
    jal draw_pixel

s5_col_next:
    addiu $t5, $t5, 1
    j s5_col_loop

s5_row_next:
    addiu $t2, $t2, 1
    j s5_row_loop

s5_done:
    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addiu $sp, $sp, 28
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_icon_7x7
# Inputs:  $a0 = x, $a1 = y, $a2 = icon_index (0..4), $a3 = color
# Purpose: Renders 7x7 pixel center card icon from icon_7x7_data bitmap table.
# ------------------------------------------------------------------------------
draw_icon_7x7:
    addiu $sp, $sp, -28
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)

    move $s0, $a0          # x
    move $s1, $a1          # y
    move $s2, $a2          # icon index
    move $s3, $a3          # color

    la $t0, icon_7x7_data
    mul $t1, $s2, 7
    addu $s4, $t0, $t1     # ptr to 7 bytes

    li $t2, 0              # row = 0
i7_row_loop:
    bge $t2, 7, i7_done
    lbu $t3, 0($s4)        # row bits (7 bits)
    addiu $s4, $s4, 1

    addu $a1, $s1, $t2     # screen Y
    move $a2, $s3          # color

    li $t5, 0              # bit col = 0..6
i7_col_loop:
    bge $t5, 7, i7_row_next
    li $t6, 6
    subu $t6, $t6, $t5     # shift = 6 - col
    srlv $t7, $t3, $t6
    andi $t7, $t7, 1
    beqz $t7, i7_col_next

    addu $a0, $s0, $t5     # screen X
    jal draw_pixel

i7_col_next:
    addiu $t5, $t5, 1
    j i7_col_loop

i7_row_next:
    addiu $t2, $t2, 1
    j i7_row_loop

i7_done:
    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addiu $sp, $sp, 28
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_sprite_indexed
# Inputs:  $a0 = x, $a1 = y, $a2 = w, $a3 = h
# Stack:   0($sp) = sprite_data ptr, 4($sp) = palette ptr
# Purpose: Blits palette-indexed sprite (used for 24x24 dealer portrait).
# ------------------------------------------------------------------------------
draw_sprite_indexed:
    lw $t8, 0($sp)         # sprite_data
    lw $t9, 4($sp)         # palette

    li $t0, 0              # row = 0
dsi_row_loop:
    bge $t0, $a3, dsi_done
    addu $t1, $a1, $t0     # cur_y = y + row
    bltz $t1, dsi_row_next
    bge $t1, 128, dsi_done

    li $t2, 0              # col = 0
dsi_col_loop:
    bge $t2, $a2, dsi_row_next
    addu $t3, $a0, $t2     # cur_x = x + col

    lbu $t4, 0($t8)        # palette index
    addiu $t8, $t8, 1

    # color = palette[t4 * 4]
    sll $t5, $t4, 2
    addu $t5, $t9, $t5
    lw $t6, 0($t5)

    # bounds check x
    bltz $t3, dsi_col_next
    bge $t3, 256, dsi_col_next

    # plot pixel directly into framebuffer
    sll $t7, $t1, 8
    addu $t7, $t7, $t3
    sll $t7, $t7, 2
    lui $t5, 0x1001
    addu $t7, $t7, $t5
    sw $t6, 0($t7)

dsi_col_next:
    addiu $t2, $t2, 1
    j dsi_col_loop

dsi_row_next:
    addiu $t0, $t0, 1
    j dsi_row_loop

dsi_done:
    jr $ra

# ==============================================================================
# GRAPHICS DRAWING PRIMITIVES
# ==============================================================================

# ------------------------------------------------------------------------------
# ROUTINE: draw_pixel
# Inputs:  $a0 = x, $a1 = y, $a2 = color (0x00RRGGBB)
# Purpose: Draws single pixel with strict framebuffer bounds checking.
# ------------------------------------------------------------------------------
draw_pixel:
    # Bounds check [0, 255] and [0, 127]
    bltz $a0, dp_exit
    bge $a0, 256, dp_exit
    bltz $a1, dp_exit
    bge $a1, 128, dp_exit

    # Address = 0x10010000 + ((y * 256) + x) * 4
    sll $t0, $a1, 8
    addu $t0, $t0, $a0
    sll $t0, $t0, 2
    lui $t1, 0x1001
    addu $t1, $t1, $t0
    sw $a2, 0($t1)
dp_exit:
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: fill_rect
# Inputs:  $a0 = x, $a1 = y, $a2 = w, $a3 = h
# Stack:   0($sp) = color (0x00RRGGBB)
# Purpose: High-speed scanline rectangle blitter with bounds clipping and stride.
# ------------------------------------------------------------------------------
fill_rect:
    lw $t4, 0($sp)         # color
    blez $a2, fr_exit
    blez $a3, fr_exit
    bltz $a0, fr_exit
    bge $a0, 256, fr_exit
    bltz $a1, fr_exit
    bge $a1, 128, fr_exit

    # Clamp w so x + w <= 256
    addu $t0, $a0, $a2
    ble $t0, 256, fr_w_ok
    li $t1, 256
    subu $a2, $t1, $a0
fr_w_ok:
    # Clamp h so y + h <= 128
    addu $t0, $a1, $a3
    ble $t0, 128, fr_h_ok
    li $t1, 128
    subu $a3, $t1, $a1
fr_h_ok:

    # Start address: 0x10010000 + ((y * 256) + x) * 4
    sll $t0, $a1, 8
    addu $t0, $t0, $a0
    sll $t0, $t0, 2
    lui $t1, 0x1001
    addu $t1, $t1, $t0     # t1 = start_addr

    # Stride = (256 - w) * 4
    li $t2, 256
    subu $t2, $t2, $a2
    sll $t2, $t2, 2        # t2 = stride bytes

    move $t3, $a3          # row_count = h
fr_row_loop:
    blez $t3, fr_exit
    move $t5, $a2          # col_count = w

fr_col_loop:
    blez $t5, fr_next_row
    sw $t4, 0($t1)
    addiu $t1, $t1, 4
    addiu $t5, $t5, -1
    j fr_col_loop

fr_next_row:
    addu $t1, $t1, $t2     # skip stride to next row
    addiu $t3, $t3, -1
    j fr_row_loop

fr_exit:
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_rect_outline
# Inputs:  $a0 = x, $a1 = y, $a2 = w, $a3 = h
# Stack:   0($sp) = color
# Purpose: Draws 1-pixel hollow rectangle border.
# ------------------------------------------------------------------------------
draw_rect_outline:
    addiu $sp, $sp, -28
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)

    move $s0, $a0          # x
    move $s1, $a1          # y
    move $s2, $a2          # w
    move $s3, $a3          # h
    lw $s4, 28($sp)        # color (from caller's 0($sp))

    # Top horizontal edge (x, y, w, 1)
    move $a0, $s0
    move $a1, $s1
    move $a2, $s2
    li $a3, 1
    addiu $sp, $sp, -4
    sw $s4, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Bottom horizontal edge (x, y + h - 1, w, 1)
    move $a0, $s0
    addu $a1, $s1, $s3
    addiu $a1, $a1, -1
    move $a2, $s2
    li $a3, 1
    addiu $sp, $sp, -4
    sw $s4, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Left vertical edge (x, y, 1, h)
    move $a0, $s0
    move $a1, $s1
    li $a2, 1
    move $a3, $s3
    addiu $sp, $sp, -4
    sw $s4, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # Right vertical edge (x + w - 1, y, 1, h)
    addu $a0, $s0, $s2
    addiu $a0, $a0, -1
    move $a1, $s1
    li $a2, 1
    move $a3, $s3
    addiu $sp, $sp, -4
    sw $s4, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addiu $sp, $sp, 28
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_panel_with_shadow
# Inputs:  $a0 = x, $a1 = y, $a2 = w, $a3 = h
# Stack:   0($sp) = bg_color, 4($sp) = border_color, 8($sp) = shadow_color
# Purpose: Renders 3D beveled panel with background, outline, and drop shadow.
# ------------------------------------------------------------------------------
draw_panel_with_shadow:
    addiu $sp, $sp, -32
    sw $ra, 28($sp)
    sw $s0, 24($sp)
    sw $s1, 20($sp)
    sw $s2, 16($sp)
    sw $s3, 12($sp)
    sw $s4, 8($sp)
    sw $s5, 4($sp)
    sw $s6, 0($sp)

    move $s0, $a0          # x
    move $s1, $a1          # y
    move $s2, $a2          # w
    move $s3, $a3          # h
    lw $s4, 32($sp)        # bg_color
    lw $s5, 36($sp)        # border_color
    lw $s6, 40($sp)        # shadow_color

    # 1. Drop shadow rect at (x+1, y+1, w, h)
    addiu $a0, $s0, 1
    addiu $a1, $s1, 1
    move $a2, $s2
    move $a3, $s3
    addiu $sp, $sp, -4
    sw $s6, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # 2. Main panel body (x, y, w, h)
    move $a0, $s0
    move $a1, $s1
    move $a2, $s2
    move $a3, $s3
    addiu $sp, $sp, -4
    sw $s4, 0($sp)
    jal fill_rect
    addiu $sp, $sp, 4

    # 3. 1px border outline (x, y, w, h)
    move $a0, $s0
    move $a1, $s1
    move $a2, $s2
    move $a3, $s3
    addiu $sp, $sp, -4
    sw $s5, 0($sp)
    jal draw_rect_outline
    addiu $sp, $sp, 4

    lw $s6, 0($sp)
    lw $s5, 4($sp)
    lw $s4, 8($sp)
    lw $s3, 12($sp)
    lw $s2, 16($sp)
    lw $s1, 20($sp)
    lw $s0, 24($sp)
    lw $ra, 28($sp)
    addiu $sp, $sp, 32
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_char_3x5
# Inputs:  $a0 = x, $a1 = y, $a2 = ASCII char, $a3 = color
# Purpose: Renders single 3x5 font character.
# ------------------------------------------------------------------------------
draw_char_3x5:
    addiu $sp, $sp, -28
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)

    move $s0, $a0          # x
    move $s1, $a1          # y
    move $s2, $a2          # char
    move $s3, $a3          # color

    # Convert lowercase to uppercase ('a'..'z' -> 'A'..'Z')
    blt $s2, 97, dc_range_chk
    bgt $s2, 122, dc_range_chk
    addiu $s2, $s2, -32

dc_range_chk:
    blt $s2, 32, dc_char_exit
    bgt $s2, 93, dc_char_exit

    # Font table offset = (char - 32) * 5
    addiu $t0, $s2, -32
    mul $t0, $t0, 5
    la $t1, font_data
    addu $s4, $t1, $t0     # pointer to 5 bytes

    li $t2, 0              # row = 0..4
dc_row_loop:
    bge $t2, 5, dc_char_exit
    lbu $t3, 0($s4)        # row bits (bits 2..0)
    addiu $s4, $s4, 1

    addu $a1, $s1, $t2     # y + row
    move $a2, $s3          # color

    # Bit 2 (left column)
    andi $t4, $t3, 4
    beqz $t4, dc_bit1
    move $a0, $s0
    jal draw_pixel

dc_bit1:
    # Bit 1 (middle column)
    andi $t4, $t3, 2
    beqz $t4, dc_bit0
    addiu $a0, $s0, 1
    jal draw_pixel

dc_bit0:
    # Bit 0 (right column)
    andi $t4, $t3, 1
    beqz $t4, dc_next_row
    addiu $a0, $s0, 2
    jal draw_pixel

dc_next_row:
    addiu $t2, $t2, 1
    j dc_row_loop

dc_char_exit:
    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addiu $sp, $sp, 28
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_string_3x5
# Inputs:  $a0 = x, $a1 = y, $a2 = null-terminated string ptr, $a3 = color
# Purpose: Renders text string with 4-pixel advance per character (3px + 1px gap).
# ------------------------------------------------------------------------------
draw_string_3x5:
    addiu $sp, $sp, -24
    sw $ra, 20($sp)
    sw $s0, 16($sp)
    sw $s1, 12($sp)
    sw $s2, 8($sp)
    sw $s3, 4($sp)

    move $s0, $a0          # curr_x
    move $s1, $a1          # curr_y
    move $s2, $a2          # str ptr
    move $s3, $a3          # color

dstr_loop:
    lbu $t0, 0($s2)
    beqz $t0, dstr_done
    addiu $s2, $s2, 1

    move $a0, $s0
    move $a1, $s1
    move $a2, $t0
    move $a3, $s3
    jal draw_char_3x5

    addiu $s0, $s0, 4      # advance 4 pixels
    j dstr_loop

dstr_done:
    lw $s3, 4($sp)
    lw $s2, 8($sp)
    lw $s1, 12($sp)
    lw $s0, 16($sp)
    lw $ra, 20($sp)
    addiu $sp, $sp, 24
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_string_shadow
# Inputs:  $a0 = x, $a1 = y, $a2 = string ptr, $a3 = fg_color
# Stack:   0($sp) = shadow_color
# Purpose: Renders text with 1px offset drop shadow.
# ------------------------------------------------------------------------------
draw_string_shadow:
    addiu $sp, $sp, -28
    sw $ra, 24($sp)
    sw $s0, 20($sp)
    sw $s1, 16($sp)
    sw $s2, 12($sp)
    sw $s3, 8($sp)
    sw $s4, 4($sp)

    move $s0, $a0
    move $s1, $a1
    move $s2, $a2
    move $s3, $a3
    lw $s4, 28($sp)        # shadow_color

    # Draw shadow at (x+1, y+1)
    addiu $a0, $s0, 1
    addiu $a1, $s1, 1
    move $a2, $s2
    move $a3, $s4
    jal draw_string_3x5

    # Draw foreground at (x, y)
    move $a0, $s0
    move $a1, $s1
    move $a2, $s2
    move $a3, $s3
    jal draw_string_3x5

    lw $s4, 4($sp)
    lw $s3, 8($sp)
    lw $s2, 12($sp)
    lw $s1, 16($sp)
    lw $s0, 20($sp)
    lw $ra, 24($sp)
    addiu $sp, $sp, 28
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: draw_int_3x5
# Inputs:  $a0 = x, $a1 = y, $a2 = integer value, $a3 = color
# Purpose: Formats integer to ASCII in num_str_buf and renders it.
# ------------------------------------------------------------------------------
draw_int_3x5:
    addiu $sp, $sp, -24
    sw $ra, 20($sp)
    sw $s0, 16($sp)
    sw $s1, 12($sp)
    sw $s2, 8($sp)
    sw $s3, 4($sp)

    move $s0, $a0
    move $s1, $a1
    move $s2, $a2
    move $s3, $a3

    la $a0, num_str_buf
    move $a1, $s2
    jal int_to_string

    move $a0, $s0
    move $a1, $s1
    la $a2, num_str_buf
    move $a3, $s3
    jal draw_string_3x5

    lw $s3, 4($sp)
    lw $s2, 8($sp)
    lw $s1, 12($sp)
    lw $s0, 16($sp)
    lw $ra, 20($sp)
    addiu $sp, $sp, 24
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: int_to_string
# Inputs:  $a0 = destination buffer pointer, $a1 = unsigned/positive integer
# Purpose: Converts integer to null-terminated decimal string.
# ------------------------------------------------------------------------------
int_to_string:
    move $t0, $a0          # dst
    move $t1, $a1          # val

    bnez $t1, its_nonzero
    # Value is 0: store '0', ' '
    li $t2, 48             # '0'
    sb $t2, 0($t0)
    sb $zero, 1($t0)
    jr $ra

its_nonzero:
    addiu $sp, $sp, -16
    move $t2, $sp          # stack temp pointer
    li $t3, 10

its_div_loop:
    divu $t1, $t3
    mflo $t1               # quotient
    mfhi $t4               # remainder
    addiu $t4, $t4, 48     # '0' + digit
    sb $t4, 0($t2)
    addiu $t2, $t2, 1
    bnez $t1, its_div_loop

its_copy_loop:
    ble $t2, $sp, its_done
    addiu $t2, $t2, -1
    lbu $t4, 0($t2)
    sb $t4, 0($t0)
    addiu $t0, $t0, 1
    j its_copy_loop

its_done:
    sb $zero, 0($t0)       # null terminator
    addiu $sp, $sp, 16
    jr $ra

# ------------------------------------------------------------------------------
# ROUTINE: strlen
# Inputs:  $a0 = string pointer
# Outputs: $v0 = string length in characters
# ------------------------------------------------------------------------------
strlen:
    move $v0, $zero
sl_loop:
    lbu $t0, 0($a0)
    beqz $t0, sl_done
    addiu $v0, $v0, 1
    addiu $a0, $a0, 1
    j sl_loop
sl_done:
    jr $ra

# ==============================================================================
# END OF FILE: blackjack.asm
# ==============================================================================
