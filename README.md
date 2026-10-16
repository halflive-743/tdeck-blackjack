# LilyGo T-Deck Blackjack for WADAMESH (Lua 5.4)

A casino **Blackjack (21)** application built for the **LilyGo T-Deck** (and other MeshCore / WADAMESH boards) using the on-device **WADAMESH Lua App SDK (`wada.*` API v1)**.

## Project Files

- [`blackjack.lua`](blackjack.lua) — Standalone Lua app ready to copy to your T-Deck.
- [`blackjack.json`](blackjack.json) — Optional WADAMESH app drawer / Store manifest.
- [`deploy/apps/blackjack/1.0/`](deploy/apps/blackjack/1.0) — Structured for USB serial sideloading (`scripts/sideload_app.py`) or submitting to the WADAMESH Store.
- [`simulator.html`](simulator.html) — Interactive desktop browser simulator of the 320×240 T-Deck screen, trackball, and physical keyboard.
- [`test_harness.lua`](test_harness.lua) — Automated SDK constraint and gameplay verification script.

---

## Features

- **Authentic 6-Deck Shoe:** Hardware RNG (`wada.sys.random`) Fisher-Yates shuffle with automatic cut-card reshuffle.
- **Full Casino Rules:**
  - **3:2 Natural Blackjack** payout
  - **Hit**, **Stand**, **Double Down**, and **Split Pairs** (side-by-side split hand view with active hand indicator)
  - Soft/Hard Ace live valuation (e.g., `YOU: 7 / 17`)
  - Animated dealer draw cadence (`wada.timer.every(420)`) standing on 17
- **Font-Independent Vector Suit Pips:** Custom-rendered Spade, Heart, Diamond, and Club vector icons on `wada.ui.canvas` so cards render crisply regardless of the firmware's active LVGL font subset.
- **Persistent Bankroll & Home Widget:**
  - Automatically saves bankroll, all-time peak bankroll, last wager, and win rate via `wada.store` (written only at round completion and app close to avoid flash wear).
  - Publishes live bankroll and win rate to the WADAMESH **Home Screen Widget** (`wada.widget.set`).
  - Automatic **$500 Bailout** if your bankroll hits `$0`.

---

## Installing on Your LilyGo T-Deck

### Option 1: microSD Card (Fastest)
1. Insert your T-Deck's microSD card into your computer.
2. Copy [`blackjack.lua`](blackjack.lua) and [`blackjack.json`](blackjack.json) to:
   ```text
   /meshcomod/apps/blackjack.lua
   /meshcomod/apps/blackjack.json
   ```
   *(Note: On SD-backed WADAMESH devices, apps live under `/meshcomod/apps/`, not `/apps/` at the root of the card.)*
3. Pop the card back into the T-Deck and open the **Apps** drawer — **Blackjack** will appear with the game icon.

### Option 2: USB Serial Sideload (Without Removing SD Card)
Using the WADAMESH repository's sideload script over USB serial:
```bash
python scripts/sideload_app.py --port COM3 --reboot deploy/apps/blackjack/1.0
```

---

## Controls on the LilyGo T-Deck

| Input Method | Action |
| :--- | :--- |
| **Touchscreen** | Tap any action button on the bottom bar (`HIT`, `STAND`, `DBL`, `SPLIT`, bet chips, `DEAL`), tap the table after a round to re-deal, or tap top-right to mute/unmute beeps. |
| **Keyboard `H`** | **Hit** (during play) or **Deal** (between rounds) |
| **Keyboard `S`** | **Stand** |
| **Keyboard `D`** | **Double Down** (during play) or **Deal** (between rounds) |
| **Keyboard `P`** | **Split** pair |
| **Keyboard `B`** | Return to **Betting** screen after a hand |
| **Keyboard `W` / `Z` or `+` / `-`** | Increase / Decrease wager by `$10` |
| **Keyboard `X` / `C`** | **Max** bet / **Clear** to minimum bet (`$10`) |
| **Keyboard `A` / `L`** | Move button highlight left / right |
| **Keyboard `Enter` / `Space`** | Activate highlighted button |
| **Keyboard `M`** | Toggle sound (`wada.sys.beep`) |
| **Trackball Left / Right** | Cycle focus highlight across bottom bar buttons |
| **Trackball Up / Down** | Adjust wager by `$25` (betting) or Hit / Stand (playing) |
| **Trackball Click** | Activate focused button |
