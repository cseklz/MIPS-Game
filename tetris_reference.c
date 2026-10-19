/* ============================================================================
 * File: tetris_reference.c
 * Course: Module 4 - MIPS Game Project (ZyBooks Chapter 4)
 * Architecture Planning & Reference Implementation for MARS 4.5 MIPS Assembly
 *
 * Description:
 *   High-level C99 reference implementation modeling the game state, procedures,
 *   register conventions, 7-bag randomizer, rotation offsets, collision detection,
 *   wall kicks, line clearing, scoring, and gravity loop for the Tetris MIPS
 *   custom game project.
 *   This implementation mirrors the exact procedure contracts, data tables,
 *   and control flow found in tetris.asm.
 * ============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <stdint.h>

#define BOARD_COLS      10
#define BOARD_ROWS      20
#define NUM_PIECES      7
#define NUM_ROTATIONS   4
#define BLOCKS_PER_PIECE 4

/* Game States (Mirrors tetris.asm STATE_* constants) */
typedef enum {
    STATE_TITLE    = 0,
    STATE_PLAYING  = 1,
    STATE_PAUSED   = 2,
    STATE_GAMEOVER = 3
} GameState;

/* Tetromino Piece Types */
typedef enum {
    PIECE_I = 0,
    PIECE_O = 1,
    PIECE_T = 2,
    PIECE_S = 3,
    PIECE_Z = 4,
    PIECE_J = 5,
    PIECE_L = 6
} PieceType;

/* Global Game State Variables (Mirrors MIPS .data segment at 0x10020000) */
static GameState game_state       = STATE_TITLE;
static uint32_t  score            = 0;
static uint32_t  high_score       = 0;
static uint32_t  lines_cleared    = 0;
static uint32_t  level            = 1;
static uint32_t  gravity_interval = 800; /* milliseconds */
static uint32_t  last_gravity_time = 0;
static int       needs_redraw     = 1;
static int       hud_needs_redraw = 1;

/* Active Piece State */
static int curr_type = 0;  /* 0..6 */
static int curr_rot  = 0;  /* 0..3 */
static int curr_x    = 3;  /* Board col: 0..9 */
static int curr_y    = 0;  /* Board row: 0..19 */
static int ghost_y   = 0;

/* Next Piece & 7-Bag Randomizer */
static int next_type = 0;
static int bag_index = 7;
static uint8_t bag[7] = {0, 1, 2, 3, 4, 5, 6};
static uint32_t rng_seed = 0x12345678;

/* Playfield Board: 10 x 20 bytes (0 = empty, 1..7 = locked piece color) */
static uint8_t board[BOARD_ROWS][BOARD_COLS];

/* Tetromino Rotation Offset Table (7 pieces * 4 rotations * 4 blocks * (X,Y)) */
static const int piece_offsets[NUM_PIECES][NUM_ROTATIONS][BLOCKS_PER_PIECE][2] = {
    /* Piece 0: I */
    {
        {{0,0}, {1,0}, {2,0}, {3,0}}, /* Rot 0 */
        {{2,0}, {2,1}, {2,2}, {2,3}}, /* Rot 1 */
        {{0,1}, {1,1}, {2,1}, {3,1}}, /* Rot 2 */
        {{1,0}, {1,1}, {1,2}, {1,3}}  /* Rot 3 */
    },
    /* Piece 1: O */
    {
        {{1,0}, {2,0}, {1,1}, {2,1}},
        {{1,0}, {2,0}, {1,1}, {2,1}},
        {{1,0}, {2,0}, {1,1}, {2,1}},
        {{1,0}, {2,0}, {1,1}, {2,1}}
    },
    /* Piece 2: T */
    {
        {{1,0}, {0,1}, {1,1}, {2,1}},
        {{1,0}, {1,1}, {2,1}, {1,2}},
        {{0,1}, {1,1}, {2,1}, {1,2}},
        {{1,0}, {0,1}, {1,1}, {1,2}}
    },
    /* Piece 3: S */
    {
        {{1,0}, {2,0}, {0,1}, {1,1}},
        {{1,0}, {1,1}, {2,1}, {2,2}},
        {{1,1}, {2,1}, {0,2}, {1,2}},
        {{0,0}, {0,1}, {1,1}, {1,2}}
    },
    /* Piece 4: Z */
    {
        {{0,0}, {1,0}, {1,1}, {2,1}},
        {{2,0}, {1,1}, {2,1}, {1,2}},
        {{0,1}, {1,1}, {1,2}, {2,2}},
        {{1,0}, {0,1}, {1,1}, {0,2}}
    },
    /* Piece 5: J */
    {
        {{0,0}, {0,1}, {1,1}, {2,1}},
        {{1,0}, {2,0}, {1,1}, {1,2}},
        {{0,1}, {1,1}, {2,1}, {2,2}},
        {{1,0}, {1,1}, {0,2}, {1,2}}
    },
    /* Piece 6: L */
    {
        {{2,0}, {0,1}, {1,1}, {2,1}},
        {{1,0}, {1,1}, {1,2}, {2,2}},
        {{0,1}, {1,1}, {2,1}, {0,2}},
        {{0,0}, {1,0}, {1,1}, {1,2}}
    }
};

/* Forward Declarations of Procedures (1-to-1 with tetris.asm) */
void restart_game(void);
void show_title_screen(void);
int  rand_int(int max_val);
void shuffle_bag(void);
int  get_next_bag_piece(void);
bool spawn_piece(void);
bool validate_position(int piece_type, int rot, int bx, int by);
bool move_piece(int dx, int dy);
bool rotate_piece(int dir);
void calculate_ghost_y(void);
void soft_drop(void);
void hard_drop(void);
void lock_piece(void);
int  check_and_clear_rows(void);
void handle_input(char key);
void update_gravity(uint32_t current_time_ms);
void display_board_console(void);

/* ============================================================================
 * Procedure Implementations
 * ============================================================================
 */

/**
 * rand_int:
 * Linear congruential generator mirroring MARS MIPS pseudorandom syscall / LCG.
 */
int rand_int(int max_val) {
    if (max_val <= 0) return 0;
    rng_seed = rng_seed * 1103515245 + 12345;
    return (int)((rng_seed >> 16) % (uint32_t)max_val);
}

/**
 * shuffle_bag:
 * Fisher-Yates 7-bag randomizer guaranteeing balanced tetromino distribution.
 */
void shuffle_bag(void) {
    for (int i = 0; i < 7; i++) {
        bag[i] = (uint8_t)i;
    }
    for (int i = 6; i > 0; i--) {
        int j = rand_int(i + 1);
        uint8_t tmp = bag[i];
        bag[i] = bag[j];
        bag[j] = tmp;
    }
    bag_index = 0;
}

/**
 * get_next_bag_piece:
 * Returns the next piece from the 7-bag, automatically reshuffling on exhaustion.
 */
int get_next_bag_piece(void) {
    if (bag_index >= 7) {
        shuffle_bag();
    }
    return bag[bag_index++];
}

/**
 * restart_game:
 * Clears the 10x20 board, resets stats, shuffles initial bag, and spawns first piece.
 */
void restart_game(void) {
    memset(board, 0, sizeof(board));
    score = 0;
    lines_cleared = 0;
    level = 1;
    gravity_interval = 800;
    game_state = STATE_PLAYING;
    shuffle_bag();
    next_type = get_next_bag_piece();
    spawn_piece();
    needs_redraw = 1;
    hud_needs_redraw = 1;
}

/**
 * show_title_screen:
 * Enters STATE_TITLE.
 */
void show_title_screen(void) {
    game_state = STATE_TITLE;
    needs_redraw = 1;
}

/**
 * spawn_piece:
 * Promotes next_type to active piece, generates new next_type, and checks game over.
 */
bool spawn_piece(void) {
    curr_type = next_type;
    curr_rot = 0;
    curr_x = (curr_type == PIECE_O) ? 4 : 3;
    curr_y = 0;
    next_type = get_next_bag_piece();

    if (!validate_position(curr_type, curr_rot, curr_x, curr_y)) {
        game_state = STATE_GAMEOVER;
        if (score > high_score) high_score = score;
        return false;
    }
    calculate_ghost_y();
    return true;
}

/**
 * validate_position:
 * Checks whether the piece at (bx, by) with given rotation intersects boundaries or occupied cells.
 */
bool validate_position(int piece_type, int rot, int bx, int by) {
    for (int b = 0; b < BLOCKS_PER_PIECE; b++) {
        int px = bx + piece_offsets[piece_type][rot][b][0];
        int py = by + piece_offsets[piece_type][rot][b][1];

        /* Bounds check */
        if (px < 0 || px >= BOARD_COLS) return false;
        if (py < 0 || py >= BOARD_ROWS) return false;

        /* Collision with locked cells */
        if (board[py][px] != 0) return false;
    }
    return true;
}

/**
 * move_piece:
 * Attempts horizontal or vertical translation. Returns true if successful.
 */
bool move_piece(int dx, int dy) {
    int nx = curr_x + dx;
    int ny = curr_y + dy;
    if (validate_position(curr_type, curr_rot, nx, ny)) {
        curr_x = nx;
        curr_y = ny;
        calculate_ghost_y();
        needs_redraw = 1;
        return true;
    }
    return false;
}

/**
 * rotate_piece:
 * Clockwise (dir = 1) or counterclockwise (dir = -1) rotation with wall kick tests.
 */
bool rotate_piece(int dir) {
    int new_rot = (curr_rot + dir + NUM_ROTATIONS) % NUM_ROTATIONS;

    /* Test 1: Standard in-place rotation */
    if (validate_position(curr_type, new_rot, curr_x, curr_y)) {
        curr_rot = new_rot;
        calculate_ghost_y();
        needs_redraw = 1;
        return true;
    }

    /* Test 2: Wall kick 1 cell right */
    if (validate_position(curr_type, new_rot, curr_x + 1, curr_y)) {
        curr_x += 1;
        curr_rot = new_rot;
        calculate_ghost_y();
        needs_redraw = 1;
        return true;
    }

    /* Test 3: Wall kick 1 cell left */
    if (validate_position(curr_type, new_rot, curr_x - 1, curr_y)) {
        curr_x -= 1;
        curr_rot = new_rot;
        calculate_ghost_y();
        needs_redraw = 1;
        return true;
    }

    /* Test 4: Extended 2-cell kick for I-tetromino */
    if (curr_type == PIECE_I) {
        if (validate_position(curr_type, new_rot, curr_x + 2, curr_y)) {
            curr_x += 2;
            curr_rot = new_rot;
            calculate_ghost_y();
            needs_redraw = 1;
            return true;
        }
        if (validate_position(curr_type, new_rot, curr_x - 2, curr_y)) {
            curr_x -= 2;
            curr_rot = new_rot;
            calculate_ghost_y();
            needs_redraw = 1;
            return true;
        }
    }

    return false;
}

/**
 * calculate_ghost_y:
 * Projects the active piece straight down to determine the landing shadow position.
 */
void calculate_ghost_y(void) {
    int test_y = curr_y;
    while (validate_position(curr_type, curr_rot, curr_x, test_y + 1)) {
        test_y++;
    }
    ghost_y = test_y;
}

/**
 * soft_drop:
 * Drops active piece by 1 cell; awards 1 bonus point per cell.
 */
void soft_drop(void) {
    if (move_piece(0, 1)) {
        score += 1;
        hud_needs_redraw = 1;
    } else {
        lock_piece();
    }
}

/**
 * hard_drop:
 * Instantly snaps piece to ghost_y, awards 2 bonus points per cell dropped, and locks.
 */
void hard_drop(void) {
    int drop_distance = ghost_y - curr_y;
    curr_y = ghost_y;
    score += (uint32_t)(drop_distance * 2);
    hud_needs_redraw = 1;
    lock_piece();
}

/**
 * lock_piece:
 * Bakes the 4 blocks of current piece into the board, checks line clears, and spawns next.
 */
void lock_piece(void) {
    for (int b = 0; b < BLOCKS_PER_PIECE; b++) {
        int px = curr_x + piece_offsets[curr_type][curr_rot][b][0];
        int py = curr_y + piece_offsets[curr_type][curr_rot][b][1];
        if (px >= 0 && px < BOARD_COLS && py >= 0 && py < BOARD_ROWS) {
            board[py][px] = (uint8_t)(curr_type + 1);
        }
    }
    check_and_clear_rows();
    spawn_piece();
    needs_redraw = 1;
    hud_needs_redraw = 1;
}

/**
 * check_and_clear_rows:
 * Scans board bottom-to-top, collapses full rows, updates score according to classic formula:
 * 1 row = 100 * level, 2 rows = 300 * level, 3 rows = 500 * level, 4 rows = 800 * level.
 */
int check_and_clear_rows(void) {
    int cleared = 0;
    int write_row = BOARD_ROWS - 1;

    for (int read_row = BOARD_ROWS - 1; read_row >= 0; read_row--) {
        bool full = true;
        for (int x = 0; x < BOARD_COLS; x++) {
            if (board[read_row][x] == 0) {
                full = false;
                break;
            }
        }

        if (full) {
            cleared++;
        } else {
            if (write_row != read_row) {
                for (int x = 0; x < BOARD_COLS; x++) {
                    board[write_row][x] = board[read_row][x];
                }
            }
            write_row--;
        }
    }

    /* Zero out newly cleared top rows */
    while (write_row >= 0) {
        for (int x = 0; x < BOARD_COLS; x++) {
            board[write_row][x] = 0;
        }
        write_row--;
    }

    /* Scoring calculation */
    if (cleared > 0) {
        lines_cleared += (uint32_t)cleared;
        uint32_t base_pts = 0;
        switch (cleared) {
            case 1: base_pts = 100; break;
            case 2: base_pts = 300; break;
            case 3: base_pts = 500; break;
            case 4: base_pts = 800; break;
            default: base_pts = 800; break;
        }
        score += base_pts * level;

        /* Level up every 10 lines */
        uint32_t new_level = (lines_cleared / 10) + 1;
        if (new_level > level) {
            level = new_level;
            /* Speed up gravity */
            if (gravity_interval > 120) {
                gravity_interval -= 60;
            }
        }
        if (score > high_score) high_score = score;
    }

    return cleared;
}

/**
 * handle_input:
 * Processes ASCII keys received from MMIO receiver register 0xFFFF0004.
 */
void handle_input(char key) {
    if (key == 'r' || key == 'R') {
        restart_game();
        return;
    }
    if (key == 'q' || key == 'Q') {
        show_title_screen();
        return;
    }

    if (game_state == STATE_TITLE) {
        if (key == ' ' || key == '\n' || key == '\r') {
            restart_game();
        }
        return;
    }

    if (game_state == STATE_GAMEOVER) {
        if (key == 'r' || key == 'R' || key == ' ') {
            restart_game();
        }
        return;
    }

    if (game_state == STATE_PAUSED) {
        if (key == 'p' || key == 'P') {
            game_state = STATE_PLAYING;
            needs_redraw = 1;
            hud_needs_redraw = 1;
        }
        return;
    }

    if (game_state == STATE_PLAYING) {
        switch (key) {
            case 'a': case 'A': move_piece(-1, 0); break;
            case 'd': case 'D': move_piece(1, 0); break;
            case 's': case 'S': soft_drop(); break;
            case 'w': case 'W': rotate_piece(1); break;   /* Clockwise */
            case 'z': case 'Z': rotate_piece(-1); break;  /* Counterclockwise */
            case ' ':           hard_drop(); break;
            case 'p': case 'P':
                game_state = STATE_PAUSED;
                needs_redraw = 1;
                break;
            default: break; /* Discard unhandled keys */
        }
    }
}

/**
 * update_gravity:
 * Periodic timer callback advancing active tetromino downward.
 */
void update_gravity(uint32_t current_time_ms) {
    if (game_state != STATE_PLAYING) return;
    if (current_time_ms - last_gravity_time >= gravity_interval) {
        last_gravity_time = current_time_ms;
        if (!move_piece(0, 1)) {
            lock_piece();
        }
    }
}

/**
 * display_board_console:
 * Debug helper printing the ASCII representation of the playfield and HUD.
 */
void display_board_console(void) {
    printf("\n=== TETRIS (Score: %u | Lines: %u | Level: %u) ===\n", score, lines_cleared, level);
    for (int y = 0; y < BOARD_ROWS; y++) {
        printf("|");
        for (int x = 0; x < BOARD_COLS; x++) {
            /* Check active piece */
            bool is_active = false;
            for (int b = 0; b < BLOCKS_PER_PIECE; b++) {
                if (curr_x + piece_offsets[curr_type][curr_rot][b][0] == x &&
                    curr_y + piece_offsets[curr_type][curr_rot][b][1] == y) {
                    is_active = true;
                    break;
                }
            }
            if (is_active) {
                printf("#");
            } else if (board[y][x] != 0) {
                printf("O");
            } else {
                printf(".");
            }
        }
        printf("|\n");
    }
    printf("+----------+\n");
}
