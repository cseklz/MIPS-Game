# ==============================================================================
# TIC-TAC-TOE IN MIPS ASSEMBLY FOR MARS (BITMAP + KEYBOARD MMIO)
# ==============================================================================
# A complete, two-player Tic-Tac-Toe game designed for MARS using:
#   1. MARS Bitmap Display tool for graphics.
#   2. MARS Keyboard and Display MMIO Simulator for instant, freeze-free input.
#
# REQUIRED MARS TOOL CONFIGURATIONS:
# ------------------------------------------------------------------------------
# Tool 1: Bitmap Display (Tools -> Bitmap Display)
#   - Unit Width in Pixels:     4
#   - Unit Height in Pixels:    4
#   - Display Width in Pixels:  512
#   - Display Height in Pixels: 512
#   - Base address for display: 0x10010000 (static data)
#   -> Click "Connect to MIPS"
#
# Tool 2: Keyboard and Display MMIO Simulator (Tools -> Keyboard and Display MMIO Simulator)
#   -> Click "Connect to MIPS"
#   -> Players simply press keys '1' through '9' directly into the bottom
#      "Keyboard" text area (no need to press Enter!).
#
# WHY KEYBOARD MMIO?
# ------------------------------------------------------------------------------
# Standard console input (syscall 5) in MARS 4.5 frequently freezes/deadlocks
# on modern macOS and Java runtime environments because the Swing "Run I/O"
# document listener loses focus or drops newline events.
# Memory-Mapped I/O (MMIO at 0xFFFF0000) completely bypasses the Java Swing
# console bug, providing instantaneous, reliable single-keystroke input.
#
# BOARD MAPPING (Keys 1 to 9):
# ------------------------------------------------------------------------------
#         1 | 2 | 3          Index 0 | Index 1 | Index 2
#        ---+---+---        ---------+---------+---------
#         4 | 5 | 6          Index 3 | Index 4 | Index 5
#        ---+---+---        ---------+---------+---------
#         7 | 8 | 9          Index 6 | Index 7 | Index 8
#
#   Internal cell values:
#     0 = Empty
#     1 = Player O (Vibrant Cyan)
#     2 = Player X (Coral Red)
#
# STARTING-PLAYER RULE (Invisible switching):
# ------------------------------------------------------------------------------
#   - Game 1: Player O always starts.
#   - Decisive Game: Loser of the most recent decisive game starts next game.
#   - Tie Game: Does NOT change last_loser. The next game starts with whoever
#               lost the last decisive game (or Player O if no one has lost yet).
# ==============================================================================

.data

# ------------------------------------------------------------------------------
# 1. FRAMEBUFFER (128x128 pixels * 4 bytes/pixel = 65,536 bytes)
# ------------------------------------------------------------------------------
# Placed first in .data so it starts exactly at 0x10010000.
framebuffer:        .space 65536

# ------------------------------------------------------------------------------
# 2. COLOR PALETTE (24-bit RGB words: 0x00RRGGBB)
# ------------------------------------------------------------------------------
.align 2
COLOR_BG:           .word 0x00181A24    # Dark Slate Navy (background)
COLOR_GRID:         .word 0x00A0AAB8    # Crisp Silver-Slate (grid lines)
COLOR_O:            .word 0x0000D4FF    # Vibrant Sky Cyan (Player O)
COLOR_X:            .word 0x00FF4B4B    # Vibrant Coral Red (Player X)
COLOR_WIN:          .word 0x00FFD700    # Radiant Gold (Winning strike line)

# ------------------------------------------------------------------------------
# 3. PERSISTENT GAME STATE (Survives board resets across rounds)
# ------------------------------------------------------------------------------
.align 2
last_loser:         .word 0             # 0 = none yet (fallback O), 1 = O, 2 = X

# ------------------------------------------------------------------------------
# 4. PER-GAME STATE (Reset at the start of each round)
# ------------------------------------------------------------------------------
.align 2
current_player:     .word 1             # Current turn: 1 = O, 2 = X
move_count:         .word 0             # Moves played so far (0..9)

# 3x3 board representation: 9 words for indices 0 to 8.
# 0 = Empty, 1 = Player O, 2 = Player X
board:              .word 0, 0, 0, 0, 0, 0, 0, 0, 0

# ------------------------------------------------------------------------------
# 5. WINNING PATTERNS TABLE
# ------------------------------------------------------------------------------
# 8 winning lines: 3 rows, 3 columns, 2 diagonals.
# Each entry is 3 words representing board cell indices (0..8).
win_patterns:
    .word 0, 1, 2       # Row 0
    .word 3, 4, 5       # Row 1
    .word 6, 7, 8       # Row 2
    .word 0, 3, 6       # Column 0
    .word 1, 4, 7       # Column 1
    .word 2, 5, 8       # Column 2
    .word 0, 4, 8       # Diagonal 1 (top-left to bottom-right)
    .word 2, 4, 6       # Diagonal 2 (top-right to bottom-left)

# ------------------------------------------------------------------------------
# 6. USER INTERFACE & PROMPT STRINGS
# ------------------------------------------------------------------------------
str_banner:
    .asciiz "\n=======================================================\n       MIPS TIC-TAC-TOE (BITMAP + KEYBOARD MMIO)      \n=======================================================\n"
str_game_start:
    .asciiz "--- NEW GAME STARTED ---\n"
str_color_legend:
    .asciiz "Player O: Cyan  |  Player X: Coral Red\n"
str_instructions:
    .asciiz "Controls: Press keys 1-9 in the Keyboard Simulator tool.\n\n"
str_o_starts:
    .asciiz "Player O will take the first turn.\n"
str_x_starts:
    .asciiz "Player X will take the first turn.\n"
str_prompt_o:
    .asciiz "Player O's turn (press 1-9): "
str_prompt_x:
    .asciiz "Player X's turn (press 1-9): "
str_err_range:
    .asciiz ">> Invalid key! Please press a digit between 1 and 9.\n"
str_err_taken:
    .asciiz ">> That cell is already occupied! Choose an empty cell.\n"
str_win_o:
    .asciiz "\n*******************************************************\n*                >>> PLAYER O WINS! <<<               *\n*******************************************************\n"
str_win_x:
    .asciiz "\n*******************************************************\n*                >>> PLAYER X WINS! <<<               *\n*******************************************************\n"
str_tie:
    .asciiz "\n*******************************************************\n*              >>> GAME OVER: IT'S A TIE! <<<         *\n*******************************************************\n"
str_next_game:
    .asciiz "Preparing next game in 3 seconds...\n\n"


# ==============================================================================
# CODE SEGMENT
# ==============================================================================
.text
.globl main

# ------------------------------------------------------------------------------
# PROCEDURE: main
# Overall program entry point. Initializes persistent state once and enters
# the continuous multi-game loop.
# ------------------------------------------------------------------------------
main:
    # Print program title banner
    li   $v0, 4
    la   $a0, str_banner
    syscall

    # Initialize persistent state: last_loser = 0 (no decisive game yet)
    sw   $zero, last_loser

    # Start the first game
    j    start_next_game


# ------------------------------------------------------------------------------
# PROCEDURE: start_next_game
# Prepares and starts a new game round:
#   1. Clears per-game state (board array and move_count).
#   2. Clears Bitmap Display and redraws the grid.
#   3. Determines the starting player based on last_loser:
#      - If last_loser == 0 (Game 1 or previous games tied): Player O starts.
#      - If last_loser != 0: last_loser starts.
#   4. Enters the turn-by-turn game loop.
# ------------------------------------------------------------------------------
start_next_game:
    # Reset board state and clear screen
    jal  reset_board

    # Determine starting player silently based on last_loser
    lw   $t0, last_loser
    beqz $t0, sng_default_o     # If last_loser == 0, O starts
    sw   $t0, current_player    # Otherwise, last_loser starts
    j    sng_announce

sng_default_o:
    li   $t1, 1                 # 1 = Player O
    sw   $t1, current_player

sng_announce:
    # Print round banner, color guide, and instructions
    li   $v0, 4
    la   $a0, str_game_start
    syscall
    li   $v0, 4
    la   $a0, str_color_legend
    syscall
    li   $v0, 4
    la   $a0, str_instructions
    syscall

    # Print who starts this round without revealing the loser variable
    lw   $t0, current_player
    beq  $t0, 1, sng_o_starts
    li   $v0, 4
    la   $a0, str_x_starts
    syscall
    j    game_loop

sng_o_starts:
    li   $v0, 4
    la   $a0, str_o_starts
    syscall
    j    game_loop


# ------------------------------------------------------------------------------
# PROCEDURE: game_loop
# Core game turn execution loop:
#   1. Polls Keyboard MMIO for a valid move (keys '1'..'9').
#   2. Validates cell availability.
#   3. Updates board array and increments move counter.
#   4. Graphically renders O or X in the chosen cell.
#   5. Evaluates board for a win:
#      - If won: draws win strike line, records loser into last_loser,
#        prints victory banner, pauses, and branches to start_next_game.
#   6. Evaluates board for a tie (9 moves with no winner):
#      - If tied: leaves last_loser unchanged, prints tie banner, pauses,
#        and branches to start_next_game.
#   7. If game continues: toggles current_player and repeats loop.
# ------------------------------------------------------------------------------
game_loop:
    # 1. Get validated move index (0..8) in $v0
    jal  get_move
    move $s0, $v0               # $s0 = cell index (0..8)

    # 2. Place move into board array
    lw   $s1, current_player    # $s1 = current player (1 or 2)
    move $a0, $s0
    move $a1, $s1
    jal  place_move

    # 3. Draw player's symbol (O or X) on Bitmap Display
    move $a0, $s0
    move $a1, $s1
    jal  draw_move

    # 4. Check for winner
    jal  check_winner
    # Returns $v0 = winner (0 = none, 1 = O, 2 = X), $v1 = winning pattern index (0..7)
    bnez $v0, handle_win

    # 5. Check for tie (move_count == 9)
    lw   $t0, move_count
    beq  $t0, 9, handle_tie

    # 6. Alternate turn to other player
    jal  switch_player
    j    game_loop


# ------------------------------------------------------------------------------
# PROCEDURE: handle_win
# Executes when a player wins:
#   $v0 = winning player (1 = O, 2 = X)
#   $v1 = winning pattern index (0..7)
# ------------------------------------------------------------------------------
handle_win:
    move $s2, $v0               # $s2 = winner
    move $s3, $v1               # $s3 = win pattern

    # Draw gold strike line through the 3 winning cells
    move $a0, $s3
    jal  draw_win_line

    # Determine loser and update persistent last_loser state
    # if winner == 1 (O), loser = 2 (X); else loser = 1 (O)
    beq  $s2, 1, hw_o_won

    # Player X won -> Loser is Player O (1)
    li   $t0, 1
    sw   $t0, last_loser
    li   $v0, 4
    la   $a0, str_win_x
    syscall
    j    hw_finish

hw_o_won:
    # Player O won -> Loser is Player X (2)
    li   $t0, 2
    sw   $t0, last_loser
    li   $v0, 4
    la   $a0, str_win_o
    syscall

hw_finish:
    # Inform players of next round transition
    li   $v0, 4
    la   $a0, str_next_game
    syscall

    # Pause 3000 ms so players can view the winning board on Bitmap Display
    li   $v0, 32
    li   $a0, 3000
    syscall

    # Start next game automatically
    j    start_next_game


# ------------------------------------------------------------------------------
# PROCEDURE: handle_tie
# Executes when all 9 cells are occupied with no winner:
#   CRITICAL: last_loser is NOT modified. It retains its prior value.
# ------------------------------------------------------------------------------
handle_tie:
    # Print tie message
    li   $v0, 4
    la   $a0, str_tie
    syscall

    # Inform players of next round transition
    li   $v0, 4
    la   $a0, str_next_game
    syscall

    # Pause 3000 ms so players can view the tied board on Bitmap Display
    li   $v0, 32
    li   $a0, 3000
    syscall

    # Start next game automatically
    j    start_next_game


# ------------------------------------------------------------------------------
# PROCEDURE: get_move
# Non-blocking MMIO receiver poller.
# Reads from MARS Keyboard Simulator:
#   0xFFFF0000 = Receiver Control (bit 0 = 1 when key available)
#   0xFFFF0004 = Receiver Data (ASCII value of pressed key)
#
# Loops with 20ms sleep until a valid unoccupied cell key ('1'..'9') is pressed.
# Returns:
#   $v0 = 0-based cell index (0..8)
# ------------------------------------------------------------------------------
get_move:
    subu $sp, $sp, 4
    sw   $ra, 0($sp)

gm_prompt:
    # Print prompt based on current_player
    lw   $t0, current_player
    beq  $t0, 1, gm_prompt_o

    li   $v0, 4
    la   $a0, str_prompt_x
    syscall
    j    gm_poll

gm_prompt_o:
    li   $v0, 4
    la   $a0, str_prompt_o
    syscall

gm_poll:
    # Poll Receiver Control (0xFFFF0000)
    lui  $t0, 0xFFFF
    lw   $t1, 0($t0)            # Receiver Control Register
    andi $t1, $t1, 1            # Check ready bit (bit 0)
    bnez $t1, gm_read_key       # Key is ready!

    # Sleep 20ms to yield CPU and keep simulator responsive
    li   $v0, 32
    li   $a0, 20
    syscall
    j    gm_poll

gm_read_key:
    # Read ASCII character from Receiver Data Register (0xFFFF0004)
    # Note: Loading from 0xFFFF0004 automatically clears the ready bit in MARS
    lui  $t0, 0xFFFF
    lw   $t2, 4($t0)            # $t2 = ASCII character code

    # Silently ignore Enter, Return, Backspace, and Space
    beq  $t2, 10, gm_poll       # Newline '\n'
    beq  $t2, 13, gm_poll       # Carriage return '\r'
    beq  $t2, 8,  gm_poll       # Backspace
    beq  $t2, 32, gm_poll       # Space

    # Validate character range: '1' <= char <= '9' (ASCII 49 to 57)
    li   $t3, '1'
    blt  $t2, $t3, gm_err_range
    li   $t3, '9'
    bgt  $t2, $t3, gm_err_range

    # Convert ASCII '1'..'9' to 0-based index: index = char - '1' (ASCII 49)
    addi $t4, $t2, -49          # $t4 = index (0..8)

    # Echo pressed character and newline to console
    li   $v0, 11
    move $a0, $t2
    syscall
    li   $v0, 11
    li   $a0, '\n'
    syscall

    # Check cell occupancy: board[index] must be 0
    sll  $t5, $t4, 2            # byte offset = index * 4
    lw   $t6, board($t5)
    bnez $t6, gm_err_taken      # If non-zero, already occupied

    # Valid move! Return index in $v0
    move $v0, $t4
    lw   $ra, 0($sp)
    addu $sp, $sp, 4
    jr   $ra

gm_err_range:
    # Echo the invalid character
    li   $v0, 11
    move $a0, $t2
    syscall
    li   $v0, 11
    li   $a0, '\n'
    syscall

    li   $v0, 4
    la   $a0, str_err_range
    syscall
    j    gm_prompt

gm_err_taken:
    li   $v0, 4
    la   $a0, str_err_taken
    syscall
    j    gm_prompt


# ------------------------------------------------------------------------------
# PROCEDURE: place_move
# Updates the internal board array and increments move counter.
# Arguments:
#   $a0 = cell index (0..8)
#   $a1 = player (1 = O, 2 = X)
# ------------------------------------------------------------------------------
place_move:
    # board[index] = player
    sll  $t0, $a0, 2            # index * 4
    sw   $a1, board($t0)

    # move_count++
    lw   $t1, move_count
    addi $t1, $t1, 1
    sw   $t1, move_count
    jr   $ra


# ------------------------------------------------------------------------------
# PROCEDURE: switch_player
# Toggles current_player between 1 (O) and 2 (X).
# ------------------------------------------------------------------------------
switch_player:
    lw   $t0, current_player
    beq  $t0, 1, sp_to_x
    li   $t1, 1                 # Currently X -> switch to O
    sw   $t1, current_player
    jr   $ra

sp_to_x:
    li   $t1, 2                 # Currently O -> switch to X
    sw   $t1, current_player
    jr   $ra


# ------------------------------------------------------------------------------
# PROCEDURE: check_winner
# Checks the 9 board cells against all 8 possible winning combinations.
# Returns:
#   $v0 = winner (0 = no winner, 1 = Player O, 2 = Player X)
#   $v1 = winning pattern index (0..7) if winner found
# ------------------------------------------------------------------------------
check_winner:
    la   $t0, win_patterns      # Base address of pattern table
    li   $t1, 0                 # Loop counter i = 0..7

cw_loop:
    bge  $t1, 8, cw_no_winner   # Checked all 8 patterns

    # Load 3 cell indices for current pattern
    lw   $t2, 0($t0)            # index A
    lw   $t3, 4($t0)            # index B
    lw   $t4, 8($t0)            # index C

    # Load corresponding cell values from board array
    sll  $t2, $t2, 2            # offset A
    sll  $t3, $t3, 2            # offset B
    sll  $t4, $t4, 2            # offset C

    lw   $t5, board($t2)        # val A
    lw   $t6, board($t3)        # val B
    lw   $t7, board($t4)        # val C

    # Check: val A != 0 AND val A == val B AND val B == val C
    beqz $t5, cw_next
    bne  $t5, $t6, cw_next
    bne  $t6, $t7, cw_next

    # Winner found!
    move $v0, $t5               # Winner (1 or 2)
    move $v1, $t1               # Pattern index (0..7)
    jr   $ra

cw_next:
    addi $t0, $t0, 12           # Next pattern (3 words = 12 bytes)
    addi $t1, $t1, 1
    j    cw_loop

cw_no_winner:
    li   $v0, 0                 # No winner
    li   $v1, 0
    jr   $ra


# ------------------------------------------------------------------------------
# PROCEDURE: reset_board
# Resets per-game variables and redraws an empty board on the Bitmap Display.
# Does NOT modify last_loser.
# ------------------------------------------------------------------------------
reset_board:
    subu $sp, $sp, 4
    sw   $ra, 0($sp)

    # 1. Clear 9 cells in board array
    la   $t0, board
    li   $t1, 9
rb_clear_cells:
    sw   $zero, 0($t0)
    addi $t0, $t0, 4
    addi $t1, $t1, -1
    bgtz $t1, rb_clear_cells

    # 2. Reset move counter
    sw   $zero, move_count

    # 3. Clear Bitmap Display and redraw grid
    jal  draw_board

    lw   $ra, 0($sp)
    addu $sp, $sp, 4
    jr   $ra


# ==============================================================================
# GRAPHICS & BITMAP RENDERING PROCEDURES
# ==============================================================================

# ------------------------------------------------------------------------------
# PROCEDURE: clear_screen
# Fills all 128x128 pixels (16,384 words) of the framebuffer with COLOR_BG.
# Base address: 0x10010000
# ------------------------------------------------------------------------------
clear_screen:
    lui  $t0, 0x1001            # Base address 0x10010000
    li   $t1, 16384             # 128 * 128 pixels = 16,384 words
    lw   $t2, COLOR_BG          # Background color
cs_loop:
    sw   $t2, 0($t0)
    addi $t0, $t0, 4
    addi $t1, $t1, -1
    bgtz $t1, cs_loop
    jr   $ra


# ------------------------------------------------------------------------------
# PROCEDURE: draw_pixel
# Sets a single pixel at (x, y) with safety clipping against screen boundaries.
# Arguments:
#   $a0 = x coordinate (0..127)
#   $a1 = y coordinate (0..127)
#   $a2 = 24-bit RGB color (0x00RRGGBB)
# ------------------------------------------------------------------------------
draw_pixel:
    # Bounds checking: 0 <= x < 128 and 0 <= y < 128
    bltz $a0, dp_exit
    bge  $a0, 128, dp_exit
    bltz $a1, dp_exit
    bge  $a1, 128, dp_exit

    # Target Address = 0x10010000 + (y * 128 + x) * 4
    sll  $t0, $a1, 7            # y * 128
    add  $t0, $t0, $a0          # y * 128 + x
    sll  $t0, $t0, 2            # byte offset = (y * 128 + x) * 4
    lui  $t1, 0x1001            # Base address 0x10010000
    add  $t1, $t1, $t0          # Absolute memory address
    sw   $a2, 0($t1)            # Store color word

dp_exit:
    jr   $ra


# ------------------------------------------------------------------------------
# PROCEDURE: draw_line_h
# Draws a horizontal line of contiguous pixels from (x, y) to the right.
# Arguments:
#   $a0 = start x
#   $a1 = start y
#   $a2 = length in pixels
#   $a3 = color
# ------------------------------------------------------------------------------
draw_line_h:
    blez $a2, dlh_done          # Length <= 0 -> nothing to draw

    # Starting address = 0x10010000 + (y * 128 + x) * 4
    sll  $t0, $a1, 7
    add  $t0, $t0, $a0
    sll  $t0, $t0, 2
    lui  $t1, 0x1001
    add  $t1, $t1, $t0          # Current pointer
    move $t2, $a2               # Counter

dlh_loop:
    sw   $a3, 0($t1)            # Draw pixel
    addi $t1, $t1, 4            # Advance 1 pixel right
    addi $t2, $t2, -1
    bgtz $t2, dlh_loop

dlh_done:
    jr   $ra


# ------------------------------------------------------------------------------
# PROCEDURE: draw_line_v
# Draws a vertical line of contiguous pixels from (x, y) downward.
# Arguments:
#   $a0 = start x
#   $a1 = start y
#   $a2 = length in pixels
#   $a3 = color
# ------------------------------------------------------------------------------
draw_line_v:
    blez $a2, dlv_done          # Length <= 0 -> nothing to draw

    # Starting address = 0x10010000 + (y * 128 + x) * 4
    sll  $t0, $a1, 7
    add  $t0, $t0, $a0
    sll  $t0, $t0, 2
    lui  $t1, 0x1001
    add  $t1, $t1, $t0          # Current pointer
    move $t2, $a2               # Counter

dlv_loop:
    sw   $a3, 0($t1)            # Draw pixel
    addi $t1, $t1, 512          # Advance 1 row down (128 words * 4 bytes = 512 bytes)
    addi $t2, $t2, -1
    bgtz $t2, dlv_loop

dlv_done:
    jr   $ra


# ------------------------------------------------------------------------------
# PROCEDURE: draw_board
# Clears the screen and draws the 3x3 Tic-Tac-Toe grid dividers.
# Grid layout (128x128 resolution, cell centers at 24, 64, 104):
#   - Vertical divider 1:   x = 43..44, y = 6..121 (height 116)
#   - Vertical divider 2:   x = 83..84, y = 6..121 (height 116)
#   - Horizontal divider 1: y = 43..44, x = 6..121 (width 116)
#   - Horizontal divider 2: y = 83..84, x = 6..121 (width 116)
# ------------------------------------------------------------------------------
draw_board:
    subu $sp, $sp, 4
    sw   $ra, 0($sp)

    # 1. Clear background
    jal  clear_screen

    # 2. Draw grid dividers with COLOR_GRID (2-pixel thickness)
    lw   $a3, COLOR_GRID

    # Vertical line 1 (x = 43, 44)
    li   $a0, 43
    li   $a1, 6
    li   $a2, 116
    jal  draw_line_v
    li   $a0, 44
    li   $a1, 6
    li   $a2, 116
    jal  draw_line_v

    # Vertical line 2 (x = 83, 84)
    li   $a0, 83
    li   $a1, 6
    li   $a2, 116
    jal  draw_line_v
    li   $a0, 84
    li   $a1, 6
    li   $a2, 116
    jal  draw_line_v

    # Horizontal line 1 (y = 43, 44)
    li   $a0, 6
    li   $a1, 43
    li   $a2, 116
    jal  draw_line_h
    li   $a0, 6
    li   $a1, 44
    li   $a2, 116
    jal  draw_line_h

    # Horizontal line 2 (y = 83, 84)
    li   $a0, 6
    li   $a1, 83
    li   $a2, 116
    jal  draw_line_h
    li   $a0, 6
    li   $a1, 84
    li   $a2, 116
    jal  draw_line_h

    lw   $ra, 0($sp)
    addu $sp, $sp, 4
    jr   $ra


# ------------------------------------------------------------------------------
# PROCEDURE: draw_move
# Converts board cell index (0..8) into screen coordinates (center_x, center_y)
# and draws the corresponding player's mark.
# Arguments:
#   $a0 = cell index (0..8)
#   $a1 = player (1 = O, 2 = X)
# ------------------------------------------------------------------------------
draw_move:
    subu $sp, $sp, 12
    sw   $ra, 8($sp)
    sw   $s0, 4($sp)
    sw   $s1, 0($sp)

    move $s0, $a1               # Save player

    # Calculate row = index / 3, col = index % 3
    li   $t0, 3
    div  $a0, $t0
    mflo $t1                    # row = 0, 1, 2
    mfhi $t2                    # col = 0, 1, 2

    # Calculate center coordinates:
    #   center_x = 24 + col * 40
    #   center_y = 24 + row * 40
    mul  $t2, $t2, 40
    addi $s1, $t2, 24           # $s1 = center_x
    mul  $t1, $t1, 40
    addi $a1, $t1, 24           # $a1 = center_y
    move $a0, $s1               # $a0 = center_x

    # Call draw_o or draw_x based on player
    beq  $s0, 1, dm_draw_o
    jal  draw_x
    j    dm_done

dm_draw_o:
    jal  draw_o

dm_done:
    lw   $s1, 0($sp)
    lw   $s0, 4($sp)
    lw   $ra, 8($sp)
    addu $sp, $sp, 12
    jr   $ra


# ------------------------------------------------------------------------------
# PROCEDURE: draw_o
# Draws a smooth circular ring representing Player O centered at (center_x, center_y).
# Uses circle equation dx^2 + dy^2 with inner radius 9 and outer radius 13.
# Arguments:
#   $a0 = center_x
#   $a1 = center_y
# ------------------------------------------------------------------------------
draw_o:
    subu $sp, $sp, 24
    sw   $ra, 20($sp)
    sw   $s0, 16($sp)
    sw   $s1, 12($sp)
    sw   $s2, 8($sp)
    sw   $s3, 4($sp)
    sw   $s4, 0($sp)

    move $s0, $a0               # $s0 = center_x
    move $s1, $a1               # $s1 = center_y
    lw   $s2, COLOR_O           # $s2 = color

    # Loop dy from -13 to +13
    li   $s3, -13
do_y_loop:
    bgt  $s3, 13, do_done

    # Loop dx from -13 to +13
    li   $s4, -13
do_x_loop:
    bgt  $s4, 13, do_next_y

    # Calculate dist_sq = dx*dx + dy*dy
    mul  $t0, $s4, $s4          # dx^2
    mul  $t1, $s3, $s3          # dy^2
    add  $t2, $t0, $t1          # dist_sq

    # Ring condition: 81 <= dist_sq <= 169  (9^2 <= dist_sq <= 13^2)
    blt  $t2, 81, do_next_x
    bgt  $t2, 169, do_next_x

    # Draw pixel at (center_x + dx, center_y + dy)
    add  $a0, $s0, $s4
    add  $a1, $s1, $s3
    move $a2, $s2
    jal  draw_pixel

do_next_x:
    addi $s4, $s4, 1
    j    do_x_loop

do_next_y:
    addi $s3, $s3, 1
    j    do_y_loop

do_done:
    lw   $s4, 0($sp)
    lw   $s3, 4($sp)
    lw   $s2, 8($sp)
    lw   $s1, 12($sp)
    lw   $s0, 16($sp)
    lw   $ra, 20($sp)
    addu $sp, $sp, 24
    jr   $ra


# ------------------------------------------------------------------------------
# PROCEDURE: draw_x
# Draws a bold X mark representing Player X centered at (center_x, center_y).
# Renders two crossing diagonals spanning -12 to +12 with 3-pixel thickness.
# Arguments:
#   $a0 = center_x
#   $a1 = center_y
# ------------------------------------------------------------------------------
draw_x:
    subu $sp, $sp, 24
    sw   $ra, 20($sp)
    sw   $s0, 16($sp)
    sw   $s1, 12($sp)
    sw   $s2, 8($sp)
    sw   $s3, 4($sp)
    sw   $s4, 0($sp)

    move $s0, $a0               # $s0 = center_x
    move $s1, $a1               # $s1 = center_y
    lw   $s2, COLOR_X           # $s2 = color

    # Loop d from -12 to +12
    li   $s3, -12
dx_loop:
    bgt  $s3, 12, dx_done

    # Inner offset loop for 3-pixel stroke thickness (-1, 0, +1)
    li   $s4, -1
dx_inner:
    bgt  $s4, 1, dx_next_d

    # Main diagonal stroke: (center_x + d + offset, center_y + d)
    add  $a0, $s0, $s3
    add  $a0, $a0, $s4
    add  $a1, $s1, $s3
    move $a2, $s2
    jal  draw_pixel

    # Anti-diagonal stroke: (center_x - d + offset, center_y + d)
    sub  $a0, $s0, $s3
    add  $a0, $a0, $s4
    add  $a1, $s1, $s3
    move $a2, $s2
    jal  draw_pixel

    addi $s4, $s4, 1
    j    dx_inner

dx_next_d:
    addi $s3, $s3, 1
    j    dx_loop

dx_done:
    lw   $s4, 0($sp)
    lw   $s3, 4($sp)
    lw   $s2, 8($sp)
    lw   $s1, 12($sp)
    lw   $s0, 16($sp)
    lw   $ra, 20($sp)
    addu $sp, $sp, 24
    jr   $ra


# ------------------------------------------------------------------------------
# PROCEDURE: draw_win_line
# Draws a bold radiant gold line striking across the winning 3 cells.
# Arguments:
#   $a0 = winning pattern index (0..7):
#         0: Row 0       3: Column 0    6: Diagonal 1 (\)
#         1: Row 1       4: Column 1    7: Diagonal 2 (/)
#         2: Row 2       5: Column 2
# ------------------------------------------------------------------------------
draw_win_line:
    subu $sp, $sp, 12
    sw   $ra, 8($sp)
    sw   $s0, 4($sp)
    sw   $s1, 0($sp)

    move $s0, $a0               # Save pattern index
    lw   $a3, COLOR_WIN         # Radiant gold color

    # Dispatch to specific line drawing routine
    beq  $s0, 0, dwl_row0
    beq  $s0, 1, dwl_row1
    beq  $s0, 2, dwl_row2
    beq  $s0, 3, dwl_col0
    beq  $s0, 4, dwl_col1
    beq  $s0, 5, dwl_col2
    beq  $s0, 6, dwl_diag1
    beq  $s0, 7, dwl_diag2
    j    dwl_exit

dwl_row0:
    # Row 0 horizontal line at y = 23, 24, 25 from x = 10 (length 108)
    li   $a0, 10
    li   $a1, 23
    li   $a2, 108
    jal  draw_line_h
    li   $a0, 10
    li   $a1, 24
    li   $a2, 108
    jal  draw_line_h
    li   $a0, 10
    li   $a1, 25
    li   $a2, 108
    jal  draw_line_h
    j    dwl_exit

dwl_row1:
    # Row 1 horizontal line at y = 63, 64, 65 from x = 10 (length 108)
    li   $a0, 10
    li   $a1, 63
    li   $a2, 108
    jal  draw_line_h
    li   $a0, 10
    li   $a1, 64
    li   $a2, 108
    jal  draw_line_h
    li   $a0, 10
    li   $a1, 65
    li   $a2, 108
    jal  draw_line_h
    j    dwl_exit

dwl_row2:
    # Row 2 horizontal line at y = 103, 104, 105 from x = 10 (length 108)
    li   $a0, 10
    li   $a1, 103
    li   $a2, 108
    jal  draw_line_h
    li   $a0, 10
    li   $a1, 104
    li   $a2, 108
    jal  draw_line_h
    li   $a0, 10
    li   $a1, 105
    li   $a2, 108
    jal  draw_line_h
    j    dwl_exit

dwl_col0:
    # Col 0 vertical line at x = 23, 24, 25 from y = 10 (length 108)
    li   $a0, 23
    li   $a1, 10
    li   $a2, 108
    jal  draw_line_v
    li   $a0, 24
    li   $a1, 10
    li   $a2, 108
    jal  draw_line_v
    li   $a0, 25
    li   $a1, 10
    li   $a2, 108
    jal  draw_line_v
    j    dwl_exit

dwl_col1:
    # Col 1 vertical line at x = 63, 64, 65 from y = 10 (length 108)
    li   $a0, 63
    li   $a1, 10
    li   $a2, 108
    jal  draw_line_v
    li   $a0, 64
    li   $a1, 10
    li   $a2, 108
    jal  draw_line_v
    li   $a0, 65
    li   $a1, 10
    li   $a2, 108
    jal  draw_line_v
    j    dwl_exit

dwl_col2:
    # Col 2 vertical line at x = 103, 104, 105 from y = 10 (length 108)
    li   $a0, 103
    li   $a1, 10
    li   $a2, 108
    jal  draw_line_v
    li   $a0, 104
    li   $a1, 10
    li   $a2, 108
    jal  draw_line_v
    li   $a0, 105
    li   $a1, 10
    li   $a2, 108
    jal  draw_line_v
    j    dwl_exit

dwl_diag1:
    # Main diagonal line (\) from (14, 14) to (113, 113) with thickness 3
    lw   $s1, COLOR_WIN
    li   $t0, 14
dwl_d1_loop:
    bgt  $t0, 113, dwl_exit
    move $a0, $t0
    move $a1, $t0
    move $a2, $s1
    jal  draw_pixel
    addi $a0, $t0, 1
    move $a1, $t0
    move $a2, $s1
    jal  draw_pixel
    move $a0, $t0
    addi $a1, $t0, 1
    move $a2, $s1
    jal  draw_pixel
    addi $t0, $t0, 1
    j    dwl_d1_loop

dwl_diag2:
    # Anti-diagonal line (/) from (113, 14) to (14, 113) with thickness 3
    lw   $s1, COLOR_WIN
    li   $t0, 14
dwl_d2_loop:
    bgt  $t0, 113, dwl_exit
    li   $t1, 127
    sub  $t1, $t1, $t0          # x = 127 - t
    move $a0, $t1
    move $a1, $t0
    move $a2, $s1
    jal  draw_pixel
    addi $a0, $t1, 1
    move $a1, $t0
    move $a2, $s1
    jal  draw_pixel
    move $a0, $t1
    addi $a1, $t0, 1
    move $a2, $s1
    jal  draw_pixel
    addi $t0, $t0, 1
    j    dwl_d2_loop

dwl_exit:
    lw   $s1, 0($sp)
    lw   $s0, 4($sp)
    lw   $ra, 8($sp)
    addu $sp, $sp, 12
    jr   $ra
