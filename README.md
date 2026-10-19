# Module 4: MIPS Game Project
**Course:** Computer Organization & Assembly Language Programming  
**Reading:** ZyBooks Chapter 4 (Procedures, Stack Conventions, MMIO, Framebuffer, Arrays)  
**Deliverable Document:** [`Module_4_MIPS_Game_Project.pdf`](Module_4_MIPS_Game_Project.pdf) (15-page concise deliverable)

---

## Executive Summary & Assignment Scope

This repository contains the complete interactive MIPS32 assembly deliverables for **Module 4: MIPS Game Project**. In accordance with the assignment instructions (**"DO ALL THREE (3): Tic-Tac-Toe, Blackjack, Your own custom game"**), all three full games have been implemented, tested, and documented with C planning reference code, MARS bitmap graphics, MMIO keyboard input, and comprehensive empirical test suites:

1. **Game 1: Tic-Tac-Toe** (`tictactoe.asm`, `tictactoe_reference.c`)
   - 2-player interactive board game on a 128×128 logical framebuffer.
   - Sky Cyan ring glyphs for Player O, Coral Red cross glyphs for Player X.
   - Non-blocking keyboard MMIO polling via `0xFFFF0000` / `0xFFFF0004` with 10ms sleep syscalls.
   - 8 winning line triples, full-board tie detection, and persistent loser turn-order tracking.

2. **Game 2: Blackjack "Midnight 21"** (`blackjack.asm`, `blackjack_reference.c`)
   - Balatro-inspired retro pixel-art casino table on a 256×128 logical framebuffer (1024×512 display).
   - 24×24 pixel-art dealer portrait (Jimbo) with an 8-color indexed palette.
   - Custom 3×5 typography, 5×5 suit icons (Spades, Hearts, Diamonds, Clubs), and ornate card backs.
   - 5-state Finite State Machine (OPENING, DEALING, PLAYER_TURN, DEALER_TURN, ROUND_OVER).
   - Dynamic soft Ace reduction (11 → 1), Fisher-Yates deck shuffle, and House AI dealer logic.

3. **Game 3: Custom Game - Tetris MIPS Arcade** (`tetris.asm`, `tetris_reference.c`)
   - Feature-complete retro arcade recreation of Tetris on a 128×128 logical framebuffer.
   - Standard 10×20 playfield matrix with 5×5 pixel beveled cells (Base, Highlight, Shadow).
   - All 7 official tetrominoes (I, O, T, S, Z, J, L) with distinct color palettes.
   - Real-time ghost piece landing guide projection.
   - 7-bag randomizer, multi-kick wall collision recovery (SRS wall kicks), hard drop, soft drop.
   - Dynamic HUD (Score, High Score, Level, Lines, Next Piece preview box, Controls help).
   - Stateful Paused and Game Over overlays.

---

## Repository Contents

```
.
├── Module_4_MIPS_Game_Project.pdf   # Complete 15-page single-file PDF deliverable
├── README.md                        # Documentation and running guide
├── Mars4_5.jar                      # MARS 4.5 MIPS Simulator runtime
├── tictactoe.asm                    # Game 1: Complete MIPS32 source code
├── tictactoe_reference.c            # Game 1: C99 planning & reference code
├── blackjack.asm                    # Game 2: Complete MIPS32 source code
├── blackjack_reference.c            # Game 2: C99 planning & reference code
├── tetris.asm                       # Game 3: Complete MIPS32 source code (Custom Game)
└── tetris_reference.c               # Game 3: C99 planning & reference code
```

---

## MARS 4.5 Execution Guide

### Common Prerequisites
1. Launch MARS: `java -jar Mars4_5.jar`
2. Go to **Settings**:
   - Check **"Permit extended (pseudo) instructions"**.
   - Ensure default memory configuration is active (`0x10010000` data base).
3. Connect the required MARS tools **BEFORE** running any assembly program.

---

### 1. Running Tic-Tac-Toe (`tictactoe.asm`)
1. Open `tictactoe.asm` in MARS.
2. Open **Tools → Bitmap Display**:
   - **Unit Width in Pixels:** `4`
   - **Unit Height in Pixels:** `4`
   - **Display Width in Pixels:** `512`
   - **Display Height in Pixels:** `512`
   - **Base Address for Display:** `0x10010000 (static data)`
   - Click **"Connect to MIPS"**.
3. Open **Tools → Keyboard and Display MMIO Simulator**:
   - Click **"Connect to MIPS"**.
4. Assemble (**F3**) and Run (**F5**).
5. **Controls:** Click inside the lower "Keyboard" text area of the MMIO tool. Press keys `1` through `9` to place moves on the 3×3 grid. Press `q` to quit.

---

### 2. Running Blackjack ("Midnight 21") (`blackjack.asm`)
1. Open `blackjack.asm` in MARS.
2. Open **Tools → Bitmap Display**:
   - **Unit Width in Pixels:** `4`
   - **Unit Height in Pixels:** `4`
   - **Display Width in Pixels:** `1024`
   - **Display Height in Pixels:** `512`
   - **Base Address for Display:** `0x10010000 (static data)`
   - Click **"Connect to MIPS"**.
3. Open **Tools → Keyboard and Display MMIO Simulator**:
   - Click **"Connect to MIPS"**.
4. Assemble (**F3**) and Run (**F5**).
5. **Controls:** Focus the lower MMIO "Keyboard" text area:
   - `N` / `n`: Deal new hand / advance round
   - `H` / `h`: Hit (draw another card)
   - `S` / `s`: Stand (pass to dealer AI)
   - `R` / `r`: Reset session statistics
   - `Q` / `q`: Quit game

---

### 3. Running Tetris MIPS Arcade (`tetris.asm`)
1. Open `tetris.asm` in MARS.
2. Open **Tools → Bitmap Display**:
   - **Unit Width in Pixels:** `4`
   - **Unit Height in Pixels:** `4`
   - **Display Width in Pixels:** `512`
   - **Display Height in Pixels:** `512`
   - **Base Address for Display:** `0x10010000 (static data)`
   - Click **"Connect to MIPS"**.
3. Open **Tools → Keyboard and Display MMIO Simulator**:
   - Click **"Connect to MIPS"**.
4. Assemble (**F3**) and Run (**F5**).
5. **Controls:** Focus the lower MMIO "Keyboard" text area:
   - `A` / `a`: Move tetromino Left
   - `D` / `d`: Move tetromino Right
   - `S` / `s`: Soft Drop (+1 pt per cell)
   - `W` / `w`: Rotate Clockwise (with SRS wall kicks)
   - `Z` / `z`: Rotate Counterclockwise
   - `Space`: Hard Drop (instant drop to ghost position + 2 pts per cell)
   - `P` / `p`: Pause / Unpause
   - `R` / `r`: Restart match
   - `Q` / `q`: Return to Title Screen

---

## ZyBooks Chapter 4 Learning Objectives Compliance

| Objective | Architectural Implementation | Verification Evidence |
| :--- | :--- | :--- |
| **Reusable Procedures** | Modular leaf and non-leaf procedures using `jal` and `jr $ra` | 50+ procedures across all 3 games with distinct parameters and return registers |
| **Stack & Register Conventions** | Callee-saved `$s0-$s7` and `$ra` preserved on `$sp`; double-word frame alignment | 100% MIPS ABI compliant stack frame lifecycle in all non-leaf routines |
| **Arrays & Game State** | Row-major board memory, 52-card decks, 10×20 tetromino matrices, rotation offset tables | Contiguous data segments with unsigned bounds checking and base + offset math |
| **Control Flow Translation** | While loops, finite state machines, SRS kick fallback chains, delay-slot safety | Clean branch instructions (`beq`, `bne`, `slt`, `j`) without pseudo-instruction hazards |
| **Graphic Display Output** | Direct ARGB pixel writing to framebuffer base `0x10010000` (128×128 & 256×128) | Custom palettes, font glyphs, and bounds-checked pixel plot routines |
| **Keyboard MMIO Input** | Non-blocking polling of receiver control `0xFFFF0000` & data `0xFFFF0004` | Integrated 10ms sleep syscalls (`$v0 = 32`) yielding processor time |

---

## Quality Checklist Verification

- [x] **1. The game runs using the documented steps:** Verified in MARS 4.5 on macOS across all 3 games.
- [x] **2. The graphic display is used correctly:** Authentic bitmap framebuffer manipulation at `0x10010000`.
- [x] **3. User input works as expected:** Non-blocking MMIO receiver polling eliminates Swing console deadlock.
- [x] **4. Procedures and labels have clear names:** Intuitive, self-documenting labels throughout assembly source files.
- [x] **5. Invalid input and edge cases are handled:** Out-of-bounds keys rejected, multi-ace hand reductions, wall kicks, and top-out handling verified.
- [x] **6. Test results are included:** 3 normal test cases and 3 edge-case tests documented per game (18 tests total).
- [x] **7. Sources and collaboration are acknowledged:** ZyBooks, Patterson & Hennessy, MARS documentation, and AI assistance cited.
- [x] **8. Academic integrity and collaboration policies apply:** Course syllabus and academic standards fully upheld.

---

## Citation of AI Assistance

In compliance with course academic integrity guidelines, the use of generative AI is formally acknowledged:
- **AI Tool:** Google DeepMind Antigravity / Gemini Advanced AI Pair Programming Assistant.
- **Scope of Collaboration:**
  1. High-level architecture and finite state machine planning.
  2. C99 reference code design (`tictactoe_reference.c`, `blackjack_reference.c`, `tetris_reference.c`).
  3. MIPS calling convention verification (stack double-word alignment, callee-saved register isolation).
  4. Procedural pixel-art and glyph encoding (3×5 font tables, card suit icons, Jimbo dealer sprite).
  5. Automated PDF deliverable generation and framebuffer screenshot rendering.
- **Human Verification:** All assembly instructions were assembled with `Mars4_5.jar`, verified for 0 warnings/errors, and empirically evaluated for functional accuracy.
