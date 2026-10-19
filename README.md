# Blackjack 21 for WADAMESH (Lua 5.4) — v1.2.2

A casino **Blackjack (21)** application built for **LilyGo T-Display P4 (AMOLED & LCD)**, **LilyGo T-Deck**, **Heltec V4**, **T-LoRa Pager**, and other MeshCore / WADAMESH boards using the on-device **WADAMESH Lua App SDK (`wada.*` API v1)**.

## Project Files

- [`blackjack.lua`](blackjack.lua) — Standalone Lua app ready to copy to your device (32.3 KB).
- [`blackjack.json`](blackjack.json) — WADAMESH app drawer / Store manifest (v1.2.2).
- [`deploy/apps/blackjack/1.2.2/`](deploy/apps/blackjack/1.2.2) — Structured for USB serial sideloading (`scripts/sideload_app.py`) or Store deployment.
- [`deploy/apps/blackjack/1.2.1/`](deploy/apps/blackjack/1.2.1) — v1.2.1 reference bundle.
- [`deploy/apps/blackjack/1.2/`](deploy/apps/blackjack/1.2) — v1.2 reference bundle.
- [`deploy/apps/blackjack/1.1/`](deploy/apps/blackjack/1.1) — v1.1 reference bundle.
- [`deploy/apps/blackjack/1.0/`](deploy/apps/blackjack/1.0) — v1.0 reference bundle.
- [`simulator.html`](simulator.html) — Interactive desktop browser simulator with hardware preview pills across all 8 target devices.
- [`test_harness.lua`](test_harness.lua) — Automated SDK constraint, instruction budget, and multi-device verification script.

---

## Supported Devices & Auto-Scaling

`blackjack.lua` automatically detects the host device and screen orientation on startup (`app.on_open(w, h)` / `wada.sys.board()`) and adapts its canvas architecture, layout, card dimensions, suit pips, and font sizes:

| Device | Native Resolution | App Body (`w × h`) | Canvas Tiles (`<= 480×480`) | Card Size (`cw × ch`) | Font Tiers |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **LilyGo T-Display P4 AMOLED** (Portrait) | `568 × 1232` (RM69A10) | `568 × 1166` | `2 × 3` tiles (`284 × 389`) | `99 × 138` px | `14 / 16 / 20 / 24` |
| **LilyGo T-Display P4 AMOLED** (Landscape) | `1232 × 568` (RM69A10) | `1232 × 502` | `3 × 2` tiles (`411 × 251`) | `82 × 114` px | `14 / 16 / 20 / 24` |
| **LilyGo T-Display P4 LCD** (Portrait) | `540 × 1168` (HI8561) | `540 × 1102` | `2 × 3` tiles (`270 × 368`) | `94 × 131` px | `14 / 16 / 20 / 24` |
| **LilyGo T-Display P4 LCD** (Landscape) | `1168 × 540` (HI8561) | `1168 × 474` | `3 × 1` tiles (`390 × 474`) | `79 × 110` px | `14 / 16 / 20 / 24` |
| **LilyGo T-Deck / T-Deck Plus** | `320 × 240` | `320 × 208` | `1` canvas (`320 × 208`) | `34 × 45` px | `12 / 14 / 16` |
| **Heltec V4 / Compact Portrait** | `240 × 320` | `240 × 244` | `1` canvas (`240 × 244`) | `38 × 52` px | `12 / 14 / 16` |
| **LilyGo T-LoRa Pager** | `480 × 222` | `480 × 178` | `1` canvas (`480 × 178`) | `34 × 42` px | `12 / 14 / 16` |

### Why T-Display P4 Needed a Tiled Virtual Canvas
In the WADAMESH firmware (`src/ui-touch/LuaAppHost.cpp`), `wada.ui.canvas(w, h)` enforces a hard per-canvas limit of `1..480` on both `w` and `h`:
```cpp
luaL_argcheck(L, w > 0 && w <= 480, 1, "width 1..480");
luaL_argcheck(L, h > 0 && h <= 480, 2, "height 1..480");
```
Passing the T-Display P4's native dimensions (`568×1166` or `540×1102`) directly to `wada.ui.canvas(W, H)` triggered a fatal Lua error (`bad argument #1 to 'canvas' (width 1..480)`), which `guardedCall` caught and immediately closed the app. `create_screen_canvas(W, H)` transparently tiles screens exceeding `480px` into seamless PSRAM-backed sub-canvases (`<= 480×480` each) positioned via `c:pos(tx, ty)`, routing drawing primitives only to overlapping tiles while staying well within the 100,000 VM instruction budget.

---

## Features

- **Authentic 6-Deck Shoe:** Hardware RNG (`wada.sys.random`) Fisher-Yates in-place shuffle with automatic cut-card reshuffle.
- **Full Casino Rules:**
  - **3:2 Natural Blackjack** payout
  - **Hit**, **Stand**, **Double Down**, and **Split Pairs** (side-by-side split hand view with active hand indicator)
  - Soft/Hard Ace live valuation (e.g., `PLAYER: 7 / 17`)
  - Animated dealer draw cadence (`wada.timer.every(420)`) standing on 17
- **Scalable Vector Suit Pips:** Custom-rendered Spade, Heart, Diamond, and Club vector icons on `wada.ui.canvas` that scale from `3px` mini pips on T-Deck up to `14px` large pips with dual-corner indices on the T-Display P4.
- **Persistent Bankroll & Home Widget:**
  - Automatically saves bankroll, all-time peak bankroll, last wager, and win rate via `wada.store`.
  - Publishes live bankroll and win rate to the WADAMESH **Home Screen Widget** (`wada.widget.set`).
  - Automatic **$500 Bailout** if your bankroll hits `$0`.

---

## Installing on Your Device

### Option 1: microSD Card (Fastest)
1. Insert your device's microSD card into your computer.
2. Copy [`blackjack.lua`](blackjack.lua) and [`blackjack.json`](blackjack.json) to:
   ```text
   /meshcomod/apps/blackjack.lua
   /meshcomod/apps/blackjack.json
   ```
   *(Note: On SD-backed WADAMESH devices, apps live under `/meshcomod/apps/`, not `/apps/` at the root of the card.)*
3. Insert the card back into your T-Display P4 or T-Deck and open the **Apps** drawer — **Blackjack** will appear with the game icon.

### Option 2: USB Serial Sideload (Without Removing SD Card)
Using the WADAMESH repository's sideload script over USB serial:
```bash
python scripts/sideload_app.py --port COM3 --reboot deploy/apps/blackjack/1.2.2
```

---

## Controls

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
| **Trackball / Swipe Left / Right** | Cycle focus highlight across bottom bar buttons |
| **Trackball / Swipe Up / Down** | Adjust wager by `$25` (betting) or Hit / Stand (playing) |
