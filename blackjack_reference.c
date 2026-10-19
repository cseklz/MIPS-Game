/* ============================================================================
 * File: blackjack_reference.c
 * Course: Module 4 - MIPS Game Project (ZyBooks Chapter 4)
 * Architecture Planning & Reference Implementation for MARS 4.5 MIPS Assembly
 *
 * Description:
 *   High-level C reference implementation modeling the game state, finite state
 *   machine (FSM), Fisher-Yates deck shuffle, hand evaluation with soft Ace
 *   reduction, and dealer AI rules for the "Midnight 21" MIPS project.
 *   This implementation mirrors the exact procedure boundaries and data
 *   structures in Blackjack.asm.
 * ============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <time.h>

#define DECK_SIZE   52
#define MAX_HAND    12

/* Game States (Mirrors Blackjack.asm state constants) */
typedef enum {
    OPENING     = 0,
    PLAYER_TURN = 1,
    DEALER_TURN = 2,
    ROUND_OVER  = 3,
    DEALING     = 4
} GameState;

/* Outcome Constants */
typedef enum {
    OUTCOME_NONE = 0,
    OUTCOME_WIN  = 1,
    OUTCOME_LOSS = 2,
    OUTCOME_PUSH = 3
} RoundOutcome;

/* Suits and Ranks */
static const char *SUIT_NAMES[] = {"Spades", "Hearts", "Diamonds", "Clubs"};
static const char *RANK_NAMES[] = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"};

/* Global Game State (Mirrors MIPS .data segment) */
static GameState state = OPENING;
static int deck[DECK_SIZE];
static int deck_next = 0;
static int player_hand[MAX_HAND];
static int player_count = 0;
static int dealer_hand[MAX_HAND];
static int dealer_count = 0;
static int round_counted = 0;
static RoundOutcome outcome = OUTCOME_NONE;
static int wins = 0;
static int losses = 0;
static int pushes = 0;
static const char *status_msg = "WELCOME. PRESS N TO DEAL.";

/* Forward Declarations */
void shuffle_deck(void);
int  deal_card(void);
void append_card(int *hand, int *count, int card);
int  evaluate_hand(const int *hand, int count);
bool is_blackjack(const int *hand, int count);
void start_round(void);
void check_initial(void);
void player_hit(void);
void player_stand(void);
void dealer_turn_ai(void);
void resolve_round(void);
void print_card(int card);
void print_table_state(bool reveal_dealer);

/**
 * shuffle_deck:
 * Implements Fisher-Yates shuffle over 52 cards (card ID = suit * 13 + rank).
 * Uses pseudo-random generation equivalent to MARS syscall 41 / 42.
 */
void shuffle_deck(void) {
    for (int i = 0; i < DECK_SIZE; i++) {
        deck[i] = i;
    }
    for (int i = DECK_SIZE - 1; i > 0; i--) {
        int j = rand() % (i + 1);
        int temp = deck[i];
        deck[i] = deck[j];
        deck[j] = temp;
    }
    deck_next = 0;
}

/**
 * deal_card:
 * Pops next card from deck. Re-shuffles if deck runs out.
 */
int deal_card(void) {
    if (deck_next >= DECK_SIZE) {
        shuffle_deck();
    }
    return deck[deck_next++];
}

void append_card(int *hand, int *count, int card) {
    if (*count < MAX_HAND) {
        hand[(*count)++] = card;
    }
}

/**
 * evaluate_hand:
 * Computes Blackjack hand total.
 * Aces count as 11 initially. If total > 21, each Ace is reduced to 1
 * until total <= 21 or no soft Aces remain.
 */
int evaluate_hand(const int *hand, int count) {
    int total = 0;
    int aces = 0;
    for (int i = 0; i < count; i++) {
        int rank = hand[i] % 13;
        if (rank == 0) {
            aces++;
            total += 11;
        } else if (rank >= 9) {
            total += 10; /* 10, J, Q, K */
        } else {
            total += (rank + 1); /* 2..9 */
        }
    }
    while (total > 21 && aces > 0) {
        total -= 10;
        aces--;
    }
    return total;
}

/**
 * is_blackjack:
 * Returns true if hand has exactly 2 cards totaling 21 (Natural Blackjack).
 */
bool is_blackjack(const int *hand, int count) {
    return (count == 2 && evaluate_hand(hand, count) == 21);
}

/**
 * start_round:
 * Clears hands, deals 2 cards to player and 2 cards to dealer.
 */
void start_round(void) {
    player_count = 0;
    dealer_count = 0;
    round_counted = 0;
    outcome = OUTCOME_NONE;
    state = DEALING;

    /* Deal Player 1, Dealer 1, Player 2, Dealer 2 */
    append_card(player_hand, &player_count, deal_card());
    append_card(dealer_hand, &dealer_count, deal_card());
    append_card(player_hand, &player_count, deal_card());
    append_card(dealer_hand, &dealer_count, deal_card());

    check_initial();
}

/**
 * check_initial:
 * Evaluates immediate Natural Blackjack conditions upon initial deal.
 */
void check_initial(void) {
    bool p_bj = is_blackjack(player_hand, player_count);
    bool d_bj = is_blackjack(dealer_hand, dealer_count);

    if (p_bj && d_bj) {
        state = ROUND_OVER;
        outcome = OUTCOME_PUSH;
        pushes++;
        status_msg = "BOTH BLACKJACK - PUSH";
    } else if (p_bj) {
        state = ROUND_OVER;
        outcome = OUTCOME_WIN;
        wins++;
        status_msg = "BLACKJACK! YOU WIN";
    } else if (d_bj) {
        state = ROUND_OVER;
        outcome = OUTCOME_LOSS;
        losses++;
        status_msg = "DEALER BLACKJACK";
    } else {
        state = PLAYER_TURN;
        status_msg = "YOUR TURN - HIT OR STAND";
    }
}

void player_hit(void) {
    if (state != PLAYER_TURN) return;
    append_card(player_hand, &player_count, deal_card());
    int total = evaluate_hand(player_hand, player_count);
    if (total > 21) {
        state = ROUND_OVER;
        outcome = OUTCOME_LOSS;
        losses++;
        status_msg = "YOU BUST - DEALER WINS";
    } else if (total == 21) {
        /* Auto stand on 21 */
        player_stand();
    }
}

void player_stand(void) {
    if (state != PLAYER_TURN) return;
    state = DEALER_TURN;
    status_msg = "DEALER PLAYS - STANDS ON 17";
    dealer_turn_ai();
}

/**
 * dealer_turn_ai:
 * Dealer hits on 16 or lower, stands on all 17s (hard or soft).
 */
void dealer_turn_ai(void) {
    while (evaluate_hand(dealer_hand, dealer_count) < 17) {
        append_card(dealer_hand, &dealer_count, deal_card());
    }
    resolve_round();
}

/**
 * resolve_round:
 * Compares final totals and assigns Win, Loss, or Push.
 */
void resolve_round(void) {
    state = ROUND_OVER;
    int p_tot = evaluate_hand(player_hand, player_count);
    int d_tot = evaluate_hand(dealer_hand, dealer_count);

    if (d_tot > 21) {
        outcome = OUTCOME_WIN;
        wins++;
        status_msg = "DEALER BUST - YOU WIN!";
    } else if (p_tot > d_tot) {
        outcome = OUTCOME_WIN;
        wins++;
        status_msg = "YOU WIN!";
    } else if (d_tot > p_tot) {
        outcome = OUTCOME_LOSS;
        losses++;
        status_msg = "DEALER WINS";
    } else {
        outcome = OUTCOME_PUSH;
        pushes++;
        status_msg = "PUSH - EVEN HANDS";
    }
}

void print_card(int card) {
    int suit = card / 13;
    int rank = card % 13;
    printf("[%s of %s]", RANK_NAMES[rank], SUIT_NAMES[suit]);
}

void print_table_state(bool reveal_dealer) {
    printf("\n================ MIDNIGHT 21 TABLE ================\n");
    printf("Status: %s\n", status_msg);
    printf("Record: %d Wins, %d Losses, %d Pushes\n", wins, losses, pushes);
    printf("Dealer Hand: ");
    if (!reveal_dealer && state == PLAYER_TURN) {
        print_card(dealer_hand[0]);
        printf(" [HIDDEN HOLE CARD]");
    } else {
        for (int i = 0; i < dealer_count; i++) {
            print_card(dealer_hand[i]);
            printf(" ");
        }
        printf(" (Total: %d)", evaluate_hand(dealer_hand, dealer_count));
    }
    printf("\nPlayer Hand: ");
    for (int i = 0; i < player_count; i++) {
        print_card(player_hand[i]);
        printf(" ");
    }
    printf(" (Total: %d)\n", evaluate_hand(player_hand, player_count));
    printf("===================================================\n\n");
}

int main(void) {
    srand(12345);
    shuffle_deck();
    printf("=== Midnight 21 C Reference Model ===\n");

    /* Round 1: Standard Deal & Play */
    start_round();
    print_table_state(false);

    if (state == PLAYER_TURN) {
        printf("Action: Player Hits...\n");
        player_hit();
        print_table_state(false);
    }
    if (state == PLAYER_TURN) {
        printf("Action: Player Stands...\n");
        player_stand();
        print_table_state(true);
    }

    return 0;
}
