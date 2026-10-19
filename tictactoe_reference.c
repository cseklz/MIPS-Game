/* ============================================================================
 * File: tictactoe_reference.c
 * Course: Module 4 - MIPS Game Project (ZyBooks Chapter 4)
 * Architecture Planning & Reference Implementation for MARS 4.5 MIPS Assembly
 *
 * Description:
 *   High-level C reference implementation modeling the game state, procedures,
 *   register conventions, and control flow for the Tic-Tac-Toe MIPS project.
 *   This implementation mirrors the exact procedure boundaries, board array
 *   indexing, win detection algorithms, and turn persistence found in
 *   TicTacToe.asm.
 * ============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>

/* Board Dimension and State Constants */
#define BOARD_CELLS 9
#define PLAYER_EMPTY 0
#define PLAYER_O     1
#define PLAYER_X     2

/* Global Game State (Mirrors MIPS .data segment) */
static int board[BOARD_CELLS];       /* 9 words, row-major: cells 0..8 */
static int current_player = 0;       /* 1 = O, 2 = X */
static int move_count = 0;           /* Total validated moves in current round */
static int winner = 0;               /* 0 = None, 1 = O, 2 = X */
static int last_loser = 0;           /* Persistent across rounds: loser starts */

/* Win Lines Lookup Table: 8 winning triples (mirrors win_lines byte array) */
static const int win_lines[8][3] = {
    {0, 1, 2}, /* Top row */
    {3, 4, 5}, /* Middle row */
    {6, 7, 8}, /* Bottom row */
    {0, 3, 6}, /* Left column */
    {1, 4, 7}, /* Middle column */
    {2, 5, 8}, /* Right column */
    {0, 4, 8}, /* Main diagonal (top-left to bottom-right) */
    {2, 4, 6}  /* Anti-diagonal (top-right to bottom-left) */
};

/* Forward Declarations of Procedures */
void init_game(void);
void reset_board(void);
void start_next_game(void);
void show_turn(void);
int  get_move(void);
bool validate_move(int index);
void place_move(int index);
int  check_winner(void);
bool check_tie(void);
void switch_player(void);
void finish_game(void);
void display_board_console(void);

/**
 * init_game:
 * Initializes persistent state ONCE at startup.
 * MIPS Equivalent: init_game label in TicTacToe.asm.
 */
void init_game(void) {
    last_loser = 0;
}

/**
 * reset_board:
 * Clears per-game state. Leaves persistent last_loser untouched.
 * MIPS Equivalent: reset_board procedure (leaf procedure).
 */
void reset_board(void) {
    for (int i = 0; i < BOARD_CELLS; i++) {
        board[i] = PLAYER_EMPTY;
    }
    current_player = 0;
    move_count = 0;
    winner = 0;
}

/**
 * start_next_game:
 * Prepares a fresh round. If a decisive loser exists, that loser starts;
 * otherwise, Player 1 (O) starts. Redraws background and grid.
 * MIPS Equivalent: start_next_game procedure.
 */
void start_next_game(void) {
    reset_board();
    if (last_loser != 0) {
        current_player = last_loser;
    } else {
        current_player = PLAYER_O;
    }
}

/**
 * show_turn:
 * Prompts user for move in console.
 * MIPS Equivalent: show_turn procedure.
 */
void show_turn(void) {
    if (current_player == PLAYER_O) {
        printf("O's turn (1-9):\n");
    } else {
        printf("X's turn (1-9):\n");
    }
}

/**
 * validate_move:
 * Checks if index is within [0, 8] and cell is unoccupied.
 * In MIPS, sltiu $t0, $a0, 9 elegantly rejects negative numbers and values >= 9.
 */
bool validate_move(int index) {
    if (index < 0 || index >= BOARD_CELLS) {
        return false;
    }
    return (board[index] == PLAYER_EMPTY);
}

/**
 * place_move:
 * Writes current player into board[index] and increments move_count.
 */
void place_move(int index) {
    board[index] = current_player;
    move_count++;
}

/**
 * check_winner:
 * Iterates through all 8 winning lines in win_lines.
 * Returns winning player ID (1 or 2), or 0 if no winner.
 */
int check_winner(void) {
    for (int i = 0; i < 8; i++) {
        int a = win_lines[i][0];
        int b = win_lines[i][1];
        int c = win_lines[i][2];
        if (board[a] != PLAYER_EMPTY &&
            board[a] == board[b] &&
            board[b] == board[c]) {
            return board[a];
        }
    }
    return 0;
}

/**
 * check_tie:
 * Returns true if 9 valid moves have occurred without a winner.
 */
bool check_tie(void) {
    return (move_count == BOARD_CELLS && check_winner() == 0);
}

/**
 * switch_player:
 * Toggles current player: 1 -> 2, 2 -> 1.
 * MIPS arithmetic trick: 3 - current_player.
 */
void switch_player(void) {
    current_player = 3 - current_player;
}

/**
 * finish_game:
 * Updates last_loser if game had a winner, prints outcome, and pauses.
 */
void finish_game(void) {
    if (winner != 0) {
        last_loser = 3 - winner; /* Loser is the opposing player */
        if (winner == PLAYER_O) {
            printf("O wins!\n");
        } else {
            printf("X wins!\n");
        }
    } else {
        /* Cat's game: last_loser remains untouched */
        printf("Tie!\n");
    }
}

/**
 * display_board_console:
 * ASCII representation of the 128x128 graphic framebuffer.
 */
void display_board_console(void) {
    printf("\n  +---+---+---+\n");
    for (int row = 0; row < 3; row++) {
        printf("  |");
        for (int col = 0; col < 3; col++) {
            int val = board[row * 3 + col];
            char sym = ' ';
            if (val == PLAYER_O) sym = 'O';
            else if (val == PLAYER_X) sym = 'X';
            printf(" %c |", sym);
        }
        printf("\n  +---+---+---+\n");
    }
    printf("\n");
}

/* Demonstration Driver */
int main(void) {
    printf("=== Tic-Tac-Toe C Planning Model ===\n");
    printf("Tic-Tac-Toe: type 1-9 in the MMIO Keyboard area; q quits.\n");
    printf("Top row: 1,2,3; middle: 4,5,6; bottom: 7,8,9.\n\n");

    init_game();
    start_next_game();

    /* Simulated sequence: O plays 5 (center), X plays 1 (top-left), etc. */
    int test_moves[] = {4, 0, 1, 3, 7}; /* 0-based indices */
    int num_moves = sizeof(test_moves) / sizeof(test_moves[0]);

    for (int i = 0; i < num_moves; i++) {
        show_turn();
        int move = test_moves[i];
        if (validate_move(move)) {
            place_move(move);
            display_board_console();
            winner = check_winner();
            if (winner != 0 || check_tie()) {
                finish_game();
                break;
            }
            switch_player();
        } else {
            printf("Invalid or occupied cell. Try again.\n");
        }
    }

    return 0;
}
