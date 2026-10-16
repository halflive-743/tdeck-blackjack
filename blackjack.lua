-- Blackjack 21 — WADAMESH Lua app for LilyGo T-Deck & MeshCore touch/keyboard boards
-- Controls:
--   Touch:     Tap any bottom-bar button, or tap the table after a hand to deal
--   Keyboard:  [H] Hit  [S] Stand  [D] Double/Deal  [P] Split  [Enter/Space] Select/Deal
--              [Left/Right] Cycle buttons  [Up/Down] Adjust bet  [M] Mute beep
--   Trackball: Swipe Left/Right to select button, Swipe Up/Down to adjust bet or Hit/Stand

local ui, sys, store, timer = wada.ui, wada.sys, wada.store, wada.timer
local C = ui.colors

local app = {}

-- Screen & canvas state
local W, H = 320, 208
local cv

-- Palette tailored for casino table on dark WadaMesh UI
local COL_FELT       = 0x0B2B1E
local COL_FELT_LINE  = 0x164A35
local COL_TOPBAR     = 0x0E1318
local COL_BOTBAR     = 0x0E1318
local COL_CARD_BG    = 0xF5F7FA
local COL_CARD_SHAD  = 0x06150E
local COL_CARD_BACK  = 0x1B4F8A
local COL_CARD_TRIM  = 0x4A8FE7
local COL_RED        = 0xD9383A
local COL_BLACK      = 0x181C24
local COL_GOLD       = 0xF2C14E
local COL_BTN        = 0x1A222B
local COL_BTN_ACT    = 0x1E3A3A
local COL_BTN_DIS    = 0x11161C
local COL_TEXT_DIM   = 0x525A65

-- Game constants
local NUM_DECKS = 6
local MIN_BET   = 10
local MAX_BET   = 1000
local START_BANK = 500

local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
-- Suits: 1=Spade, 2=Heart, 3=Diamond, 4=Club

-- Persistent state
local bankroll = START_BANK
local best_bank = START_BANK
local base_bet = 25
local wins = 0
local rounds = 0
local sound_on = true

-- Round state
-- state: "betting" | "player" | "dealer" | "done"
local state = "betting"
local shoe = {}
local dealer_hand = {}
local dealer_hide = true
local hands = {}       -- list of { cards = {}, bet = number, status = "play"|"stand"|"bust"|"bj"|"doubled", result = nil }
local cur_hand = 1
local banner_title = ""
local banner_sub = ""
local banner_col = 0x15B6A6
local dealer_Wait = 0

-- UI interactive buttons for current state
local active_btns = {}
local focus_idx = 1

-- Integer helper (LuaAppHost.cpp requires strict integers for all canvas calls)
local function I(x)
  return math.floor(tonumber(x) or 0)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function sfx()
  if sound_on and sys.beep then
    pcall(sys.beep)
  end
end

-- Safe RNG wrapper: LuaAppHost.cpp sysRandom(lo, hi) requires hi > lo
local function rand_int(lo, hi)
  lo, hi = I(lo), I(hi)
  if hi <= lo then return lo end
  local r = sys.random(lo, hi)
  if r < lo or r > hi then
    r = lo + (math.abs(r) % (hi - lo + 1))
  end
  return r
end

-- Persistence & Home Widget
local function save_stats()
  if bankroll > best_bank then
    best_bank = bankroll
  end
  store.set("bank", bankroll)
  store.set("best", best_bank)
  store.set("bet", base_bet)
  store.set("wins", wins)
  store.set("rounds", rounds)
  if wada.widget and wada.widget.set then
    local pct = rounds > 0 and I((wins * 100) / rounds) or 0
    pcall(wada.widget.set, {
      title = "Blackjack",
      value = "$" .. tostring(bankroll),
      line  = string.format("Peak $%d  ·  Win %d%% (%d/%d)", best_bank, pct, wins, rounds)
    })
  end
end

-- Shoe management
local function build_shoe()
  shoe = {}
  local idx = 1
  for _ = 1, NUM_DECKS do
    for s = 1, 4 do
      for r = 1, 13 do
        shoe[idx] = { r = r, s = s }
        idx = idx + 1
      end
    end
  end
  -- Fisher-Yates shuffle
  for i = #shoe, 2, -1 do
    local j = rand_int(1, i)
    shoe[i], shoe[j] = shoe[j], shoe[i]
  end
end

local function draw_card()
  if #shoe < 52 then
    build_shoe()
    sys.toast("Shoe reshuffled")
  end
  local c = shoe[#shoe]
  shoe[#shoe] = nil
  return c
end

-- Hand evaluation
local function card_val(r)
  if r == 1 then return 11 end
  if r >= 10 then return 10 end
  return r
end

local function eval_hand(cards)
  local total = 0
  local aces = 0
  for i = 1, #cards do
    local r = cards[i].r
    if r == 1 then
      aces = aces + 1
      total = total + 11
    elseif r >= 10 then
      total = total + 10
    else
      total = total + r
    end
  end
  while total > 21 and aces > 0 do
    total = total - 10
    aces = aces - 1
  end
  local is_soft = (aces > 0 and total <= 21)
  local is_bj = (#cards == 2 and total == 21)
  return total, is_soft, is_bj
end

local function can_split()
  if state ~= "player" or #hands ~= 1 then return false end
  local h = hands[1]
  if #h.cards ~= 2 then return false end
  if bankroll < h.bet then return false end
  return card_val(h.cards[1].r) == card_val(h.cards[2].r)
end

local function can_double()
  if state ~= "player" then return false end
  local h = hands[cur_hand]
  if not h or #h.cards ~= 2 then return false end
  return bankroll >= h.bet
end

-- Forward declarations
local rebuild_buttons
local draw_screen
local start_dealer_turn
local settle_round

-- Advance to next split hand or dealer turn
local function next_hand_or_dealer()
  if cur_hand < #hands then
    cur_hand = cur_hand + 1
    local h = hands[cur_hand]
    local total = eval_hand(h.cards)
    if total == 21 then
      h.status = "stand"
      next_hand_or_dealer()
      return
    end
    rebuild_buttons()
    draw_screen()
  else
    start_dealer_turn()
  end
end

-- Player actions
local function do_hit()
  if state ~= "player" then return end
  local h = hands[cur_hand]
  if not h or h.status ~= "play" then return end
  sfx()
  h.cards[#h.cards + 1] = draw_card()
  local total = eval_hand(h.cards)
  if total > 21 then
    h.status = "bust"
    next_hand_or_dealer()
  elseif total == 21 then
    h.status = "stand"
    next_hand_or_dealer()
  else
    rebuild_buttons()
    draw_screen()
  end
end

local function do_stand()
  if state ~= "player" then return end
  local h = hands[cur_hand]
  if not h or h.status ~= "play" then return end
  sfx()
  h.status = "stand"
  next_hand_or_dealer()
end

local function do_double()
  if not can_double() then return end
  local h = hands[cur_hand]
  sfx()
  bankroll = bankroll - h.bet
  h.bet = h.bet * 2
  h.cards[#h.cards + 1] = draw_card()
  local total = eval_hand(h.cards)
  if total > 21 then
    h.status = "bust"
  else
    h.status = "doubled"
  end
  next_hand_or_dealer()
end

local function do_split()
  if not can_split() then return end
  sfx()
  local h1 = hands[1]
  local c2 = h1.cards[2]
  h1.cards[2] = nil
  bankroll = bankroll - h1.bet

  local h2 = {
    cards = { c2, draw_card() },
    bet = h1.bet,
    status = "play"
  }
  h1.cards[2] = draw_card()
  hands[2] = h2
  cur_hand = 1

  local t1 = eval_hand(h1.cards)
  if t1 == 21 then
    h1.status = "stand"
    next_hand_or_dealer()
    return
  end
  rebuild_buttons()
  draw_screen()
end

-- Dealer turn & round settlement
start_dealer_turn = function()
  -- Check if all player hands busted
  local any_alive = false
  for i = 1, #hands do
    if hands[i].status ~= "bust" then
      any_alive = true
      break
    end
  end

  dealer_hide = false
  if not any_alive then
    settle_round()
    return
  end

  local d_tot = eval_hand(dealer_hand)
  if d_tot < 17 then
    state = "dealer"
    dealer_Wait = 1
    rebuild_buttons()
    draw_screen()
    timer.every(420)
  else
    settle_round()
  end
end

settle_round = function()
  timer.stop()
  state = "done"
  dealer_hide = false

  local d_tot, _, d_bj = eval_hand(dealer_hand)
  local net_delta = 0
  local won_any = false
  local push_any = false
  local bj_win = false

  for i = 1, #hands do
    local h = hands[i]
    local p_tot, _, p_bj = eval_hand(h.cards)
    local is_natural_bj = (p_bj and #hands == 1 and h.status == "bj")

    if h.status == "bust" then
      h.result = "BUST"
      net_delta = net_delta - h.bet
    elseif is_natural_bj and not d_bj then
      local win_amt = I((h.bet * 3) / 2)
      bankroll = bankroll + h.bet + win_amt
      net_delta = net_delta + win_amt
      h.result = "BJ!"
      won_any = true
      bj_win = true
    elseif d_bj and not is_natural_bj then
      h.result = "LOSE"
      net_delta = net_delta - h.bet
    elseif is_natural_bj and d_bj then
      bankroll = bankroll + h.bet
      h.result = "PUSH"
      push_any = true
    elseif d_tot > 21 then
      bankroll = bankroll + h.bet * 2
      net_delta = net_delta + h.bet
      h.result = "WIN"
      won_any = true
    elseif p_tot > d_tot then
      bankroll = bankroll + h.bet * 2
      net_delta = net_delta + h.bet
      h.result = "WIN"
      won_any = true
    elseif p_tot == d_tot then
      bankroll = bankroll + h.bet
      h.result = "PUSH"
      push_any = true
    else
      h.result = "LOSE"
      net_delta = net_delta - h.bet
    end
  end

  rounds = rounds + 1
  if net_delta > 0 then
    wins = wins + 1
  end

  if bj_win then
    banner_title = "BLACKJACK!"
    banner_sub = string.format("+$%d  (3:2 Payout)", net_delta)
    banner_col = COL_GOLD
  elseif net_delta > 0 then
    banner_title = d_tot > 21 and "DEALER BUSTS!" or "YOU WIN!"
    banner_sub = string.format("+$%d", net_delta)
    banner_col = C.good
  elseif net_delta < 0 then
    if #hands == 1 and hands[1].status == "bust" then
      banner_title = "BUST!"
    elseif d_bj then
      banner_title = "DEALER BLACKJACK"
    else
      banner_title = "DEALER WINS"
    end
    banner_sub = string.format("-$%d", math.abs(net_delta))
    banner_col = C.bad
  else
    banner_title = "PUSH"
    banner_sub = "Bet returned"
    banner_col = C.accent
  end

  if bankroll < MIN_BET then
    base_bet = MIN_BET
  elseif base_bet > bankroll then
    base_bet = bankroll
  end

  save_stats()
  sfx()
  rebuild_buttons()
  draw_screen()
end

-- Deal a new round
local function start_deal()
  if bankroll < MIN_BET then
    bankroll = START_BANK
    base_bet = 25
    sys.toast("Free $500 bailout chips!")
  end
  base_bet = clamp(base_bet, MIN_BET, math.min(MAX_BET, bankroll))
  bankroll = bankroll - base_bet

  dealer_hand = { draw_card(), draw_card() }
  dealer_hide = true
  hands = {
    {
      cards = { draw_card(), draw_card() },
      bet = base_bet,
      status = "play"
    }
  }
  cur_hand = 1
  banner_title = ""
  banner_sub = ""
  state = "player"
  sfx()

  local p_tot, _, p_bj = eval_hand(hands[1].cards)
  local _, _, d_bj = eval_hand(dealer_hand)

  if p_bj or d_bj then
    if p_bj then hands[1].status = "bj" end
    dealer_hide = false
    settle_round()
    return
  end

  rebuild_buttons()
  draw_screen()
end

local function adjust_bet(delta)
  if bankroll < MIN_BET then
    bankroll = START_BANK
    sys.toast("Bailout: +$500 chips")
  end
  local max_allowed = math.min(MAX_BET, bankroll)
  base_bet = clamp(base_bet + delta, MIN_BET, max_allowed)
  sfx()
  draw_screen()
end

-- Build bottom bar buttons based on state
rebuild_buttons = function()
  active_btns = {}
  if state == "betting" then
    active_btns = {
      { label = "-50",   key = "1", enabled = true, fn = function() adjust_bet(-50) end },
      { label = "-10",   key = "-", enabled = true, fn = function() adjust_bet(-10) end },
      { label = "+10",   key = "+", enabled = true, fn = function() adjust_bet(10) end },
      { label = "+50",   key = "2", enabled = true, fn = function() adjust_bet(50) end },
      { label = "MAX",   key = "x", enabled = true, fn = function() base_bet = math.min(MAX_BET, math.max(MIN_BET, bankroll)); sfx(); draw_screen() end },
      { label = "DEAL",  key = "d", primary = true, enabled = true, fn = start_deal },
    }
    focus_idx = 6
  elseif state == "player" then
    local dbl = can_double()
    local spl = can_split()
    active_btns = {
      { label = "HIT [H]",   key = "h", primary = true, enabled = true, fn = do_hit },
      { label = "STAND [S]", key = "s", enabled = true, fn = do_stand },
      { label = "DBL [D]",   key = "d", enabled = dbl,  fn = do_double },
      { label = "SPLIT [P]", key = "p", enabled = spl,  fn = do_split },
    }
    focus_idx = 1
  elseif state == "dealer" then
    active_btns = {
      { label = "DEALER DRAWING...", key = "", enabled = false, fn = function() end }
    }
    focus_idx = 1
  elseif state == "done" then
    active_btns = {
      { label = "BET [B]",      key = "b", enabled = true, fn = function() state = "betting"; rebuild_buttons(); draw_screen() end },
      { label = "-10",          key = "-", enabled = bankroll >= MIN_BET + 10, fn = function() adjust_bet(-10) end },
      { label = "+10",          key = "+", enabled = bankroll >= base_bet + 10, fn = function() adjust_bet(10) end },
      { label = "DEAL $" .. tostring(clamp(base_bet, MIN_BET, math.max(MIN_BET, bankroll))), key = "d", primary = true, enabled = true, fn = start_deal },
    }
    focus_idx = 4
  end
end

-- Vector suit pip renderer (guaranteed crisp on all LVGL font builds)
local function draw_suit_pip(x, y, suit, scale)
  x, y = I(x), I(y)
  local col = (suit == 2 or suit == 3) and COL_RED or COL_BLACK
  if scale == "small" then
    if suit == 1 then -- Spade
      cv:line(x, y - 3, x, y - 3, col, 1)
      cv:line(x - 1, y - 2, x + 1, y - 2, col, 1)
      cv:line(x - 2, y - 1, x + 2, y - 1, col, 1)
      cv:line(x - 3, y, x + 3, y, col, 1)
      cv:line(x - 2, y + 1, x + 2, y + 1, col, 1)
      cv:line(x - 1, y + 2, x + 1, y + 2, col, 1)
      cv:line(x - 2, y + 3, x + 2, y + 3, col, 1)
    elseif suit == 2 then -- Heart
      cv:line(x - 2, y - 2, x - 1, y - 2, col, 1)
      cv:line(x + 1, y - 2, x + 2, y - 2, col, 1)
      cv:line(x - 3, y - 1, x + 3, y - 1, col, 1)
      cv:line(x - 3, y, x + 3, y, col, 1)
      cv:line(x - 2, y + 1, x + 2, y + 1, col, 1)
      cv:line(x - 1, y + 2, x + 1, y + 2, col, 1)
      cv:line(x, y + 3, x, y + 3, col, 1)
    elseif suit == 3 then -- Diamond
      cv:line(x, y - 3, x, y - 3, col, 1)
      cv:line(x - 1, y - 2, x + 1, y - 2, col, 1)
      cv:line(x - 2, y - 1, x + 2, y - 1, col, 1)
      cv:line(x - 3, y, x + 3, y, col, 1)
      cv:line(x - 2, y + 1, x + 2, y + 1, col, 1)
      cv:line(x - 1, y + 2, x + 1, y + 2, col, 1)
      cv:line(x, y + 3, x, y + 3, col, 1)
    else -- Club
      cv:circle(x, y - 2, 1, col, true)
      cv:circle(x - 2, y, 1, col, true)
      cv:circle(x + 2, y, 1, col, true)
      cv:line(x, y - 1, x, y + 3, col, 1)
      cv:line(x - 1, y + 3, x + 1, y + 3, col, 1)
    end
  else
    -- Center card pip
    if suit == 1 then -- Spade
      for dy = -5, 1 do
        local hw = I((dy + 5) * 0.85)
        cv:line(x - hw, y + dy, x + hw, y + dy, col, 1)
      end
      cv:circle(x - 2, y + 1, 2, col, true)
      cv:circle(x + 2, y + 1, 2, col, true)
      cv:rect(x - 1, y + 2, 3, 4, col, true)
      cv:line(x - 3, y + 5, x + 3, y + 5, col, 1)
    elseif suit == 2 then -- Heart
      cv:circle(x - 3, y - 2, 2, col, true)
      cv:circle(x + 3, y - 2, 2, col, true)
      for dy = -1, 5 do
        local hw = math.max(0, 5 - dy)
        cv:line(x - hw, y + dy, x + hw, y + dy, col, 1)
      end
    elseif suit == 3 then -- Diamond
      for dy = -5, 5 do
        local hw = 5 - math.abs(dy)
        cv:line(x - hw, y + dy, x + hw, y + dy, col, 1)
      end
    else -- Club
      cv:circle(x, y - 3, 2, col, true)
      cv:circle(x - 3, y + 1, 2, col, true)
      cv:circle(x + 3, y + 1, 2, col, true)
      cv:rect(x - 1, y, 3, 6, col, true)
      cv:line(x - 3, y + 5, x + 3, y + 5, col, 1)
    end
  end
end

-- Draw a playing card at (x, y) of size (cw, ch)
local function draw_playing_card(x, y, cw, ch, card, hidden)
  x, y, cw, ch = I(x), I(y), I(cw), I(ch)
  -- Drop shadow
  cv:rect(x + 2, y + 2, cw, ch, COL_CARD_SHAD, true, 4)

  if hidden then
    cv:rect(x, y, cw, ch, COL_CARD_BG, true, 4)
    cv:rect(x + 2, y + 2, cw - 4, ch - 4, COL_CARD_BACK, true, 3)
    cv:rect(x + 4, y + 4, cw - 8, ch - 8, COL_CARD_TRIM, false, 2)
    -- Center emblem on card back
    local mx, my = I(x + cw / 2), I(y + ch / 2)
    cv:circle(mx, my, 5, COL_GOLD, false)
    cv:circle(mx, my, 2, COL_GOLD, true)
    return
  end

  cv:rect(x, y, cw, ch, COL_CARD_BG, true, 4)
  cv:rect(x, y, cw, ch, 0xCBD2D9, false, 4)

  local col = (card.s == 2 or card.s == 3) and COL_RED or COL_BLACK
  local rstr = RANKS[card.r]
  cv:text(x + 3, y + 2, rstr, col, 12)

  -- Top-right mini pip
  if cw >= 30 then
    draw_suit_pip(x + cw - 7, y + 8, card.s, "small")
  end

  -- Center large pip
  if ch >= 42 then
    draw_suit_pip(x + I(cw / 2), y + I(ch / 2) + 4, card.s, "large")
  else
    draw_suit_pip(x + I(cw / 2), y + I(ch / 2) + 3, card.s, "small")
  end
end

-- Draw a hand of cards centered around (cx, y)
local function draw_hand_cards(cards, cx, y, cw, ch, overlap, hide_second)
  local n = #cards
  if n == 0 then return end
  local total_w = cw + (n - 1) * overlap
  local start_x = I(cx - total_w / 2)
  for i = 1, n do
    local hx = start_x + (i - 1) * overlap
    local is_hidden = (hide_second and i == 2)
    draw_playing_card(hx, y, cw, ch, cards[i], is_hidden)
  end
end

-- Main canvas render
draw_screen = function()
  local top_h = 20
  local bot_h = 30
  local table_h = H - top_h - bot_h

  -- Felt background & decorative casino arc
  cv:fill(COL_FELT)
  cv:rect(4, top_h + 3, W - 8, table_h - 6, COL_FELT_LINE, false, 8)

  -- Top status bar
  cv:rect(0, 0, W, top_h, COL_TOPBAR, true)
  cv:line(0, top_h, W, top_h, 0x1F2933, 1)

  local bank_str = string.format("BANK $%d", bankroll)
  cv:text(6, 3, bank_str, COL_GOLD, 12)

  local active_bet = base_bet
  if state ~= "betting" and #hands > 0 then
    active_bet = 0
    for i = 1, #hands do active_bet = active_bet + hands[i].bet end
  end
  local bet_str = string.format("BET $%d", active_bet)
  cv:text(I(W * 0.40), 3, bet_str, C.accent, 12)

  local right_str = string.format("PEAK $%d %s", best_bank, sound_on and "" or "[M]")
  local rw = ui.text_w(right_str, 12)
  cv:text( math.max(I(W * 0.68), W - rw - 6), 3, right_str, C.sub, 12)

  -- Adaptive card sizing based on available height
  local cw = clamp(I(W * 0.115), 30, 42)
  local ch = clamp(I(table_h * 0.34), 40, 56)
  local overlap = I(cw * 0.62)

  if state == "betting" then
    -- Betting screen layout
    local mid_y = top_h + I(table_h / 2)
    cv:rect(I(W / 2) - 96, top_h + 10, 192, table_h - 20, 0x082016, true, 8)
    cv:rect(I(W / 2) - 96, top_h + 10, 192, table_h - 20, COL_FELT_LINE, false, 8)

    -- Decorative mini cards
    draw_playing_card(I(W / 2) - 82, top_h + 18, 30, 42, { r = 1, s = 1 }, false)
    draw_playing_card(I(W / 2) + 52, top_h + 18, 30, 42, { r = 13, s = 2 }, false)

    local title = "BLACKJACK 21"
    cv:text(I((W - ui.text_w(title, 16)) / 2), top_h + 16, title, COL_GOLD, 16)

    local sub = "3:2 Blackjack  ·  Dealer stands 17"
    cv:text(I((W - ui.text_w(sub, 12)) / 2), top_h + 36, sub, C.sub, 12)

    -- Chip badge
    local wager_lbl = string.format("WAGER: $%d", base_bet)
    local ww = ui.text_w(wager_lbl, 16)
    cv:rect(I((W - ww) / 2) - 12, mid_y + 2, ww + 24, 24, COL_BTN_ACT, true, 6)
    cv:rect(I((W - ww) / 2) - 12, mid_y + 2, ww + 24, 24, C.accent, false, 6)
    cv:text(I((W - ww) / 2), mid_y + 5, wager_lbl, C.text, 16)

    local hint = "Tap buttons or [Up/Down] Bet  [D/Enter] Deal"
    cv:text(I((W - ui.text_w(hint, 12)) / 2), top_h + table_h - 26, hint, C.sub, 12)
  else
    -- Active table layout: Dealer on top, Player on bottom
    local dealer_y = top_h + 6
    local d_cards_y = dealer_y + 15

    -- Dealer header badge
    local d_label
    if dealer_hide then
      local up_val = card_val(dealer_hand[1].r)
      d_label = string.format("DEALER: %d + ?", up_val)
    else
      local dtot, _, dbj = eval_hand(dealer_hand)
      d_label = dbj and "DEALER: 21 (BJ)" or string.format("DEALER: %d", dtot)
    end
    cv:text(10, dealer_y, d_label, C.sub, 12)
    draw_hand_cards(dealer_hand, I(W / 2), d_cards_y, cw, ch, overlap, dealer_hide)

    -- Player hand(s)
    local p_cards_y = top_h + table_h - ch - 6
    local p_label_y = p_cards_y - 15

    if #hands == 1 then
      local h = hands[1]
      local ptot, psoft, pbj = eval_hand(h.cards)
      local p_str
      if pbj then
        p_str = "YOU: 21 (BLACKJACK!)"
      elseif psoft and ptot <= 21 and state == "player" then
        p_str = string.format("YOU: %d / %d", ptot - 10, ptot)
      else
        p_str = string.format("YOU: %d", ptot)
      end
      local p_col = h.status == "bust" and C.bad or (pbj and COL_GOLD or C.text)
      cv:text(10, p_label_y, p_str, p_col, 12)
      draw_hand_cards(h.cards, I(W / 2), p_cards_y, cw, ch, overlap, false)
    else
      -- Split hands side-by-side
      local split_overlap = math.max(14, I(cw * 0.48))
      for idx = 1, 2 do
        local h = hands[idx]
        local h_cx = idx == 1 and I(W * 0.27) or I(W * 0.73)
        local is_active = (state == "player" and cur_hand == idx)
        if is_active then
          cv:rect(h_cx - 64, p_cards_y - 16, 128, ch + 19, C.accent, false, 5)
        end
        local ptot = eval_hand(h.cards)
        local tag = h.result or (h.status == "bust" and "BUST" or string.format("$%d", h.bet))
        local lbl = string.format("H%d:%d (%s)", idx, ptot, tag)
        local lcol = is_active and C.accent or (h.status == "bust" and C.bad or C.text)
        cv:text(h_cx - I(ui.text_w(lbl, 12) / 2), p_label_y, lbl, lcol, 12)
        draw_hand_cards(h.cards, h_cx, p_cards_y, cw, ch, split_overlap, false)
      end
    end

    -- Outcome banner overlay when round is finished
    if state == "done" and banner_title ~= "" then
      local bw = math.min(W - 24, math.max(156, ui.text_w(banner_title, 14) + 32))
      local bh = 34
      local bx = I((W - bw) / 2)
      local by = top_h + I((table_h - bh) / 2)
      cv:rect(bx, by, bw, bh, 0x0D131A, true, 6)
      cv:rect(bx, by, bw, bh, banner_col, false, 6)
      cv:text(I((W - ui.text_w(banner_title, 14)) / 2), by + 3, banner_title, banner_col, 14)
      cv:text(I((W - ui.text_w(banner_sub, 12)) / 2), by + 18, banner_sub, C.text, 12)
    end
  end

  -- Bottom button bar
  local by = H - bot_h
  cv:rect(0, by, W, bot_h, COL_BOTBAR, true)
  cv:line(0, by, W, by, 0x1F2933, 1)

  local nb = #active_btns
  if nb > 0 then
    local gap = 4
    local bw = I((W - gap * (nb + 1)) / nb)
    local bh = bot_h - 6
    for i = 1, nb do
      local b = active_btns[i]
      local bx = gap + (i - 1) * (bw + gap)
      local bby = by + 3
      b.x, b.y, b.w, b.h = bx, bby, bw, bh

      local bg = not b.enabled and COL_BTN_DIS or (b.primary and COL_BTN_ACT or COL_BTN)
      cv:rect(bx, bby, bw, bh, bg, true, 4)

      if i == focus_idx and b.enabled then
        cv:rect(bx, bby, bw, bh, b.primary and COL_GOLD or C.accent, false, 4)
      elseif b.enabled then
        cv:rect(bx, bby, bw, bh, 0x2B3642, false, 4)
      end

      local tcol = not b.enabled and COL_TEXT_DIM or (b.primary and COL_GOLD or C.text)
      local tw = ui.text_w(b.label, 12)
      local tx = bx + math.max(2, I((bw - tw) / 2))
      local ty = bby + I((bh - 12) / 2) - 1
      cv:text(tx, ty, b.label, tcol, 12)
    end
  end
end

-- Move focus among enabled buttons
local function cycle_focus(dir)
  local n = #active_btns
  if n == 0 then return end
  for _ = 1, n do
    focus_idx = ((focus_idx - 1 + dir) % n) + 1
    if active_btns[focus_idx] and active_btns[focus_idx].enabled then
      break
    end
  end
  draw_screen()
end

local function trigger_focused()
  local b = active_btns[focus_idx]
  if b and b.enabled and b.fn then
    b.fn()
  end
end

-- WADAMESH Lifecycle Callbacks
function app.on_open(w, h)
  W = I(w or 320)
  H = I(h or 208)

  bankroll  = tonumber(store.get("bank", START_BANK)) or START_BANK
  best_bank = tonumber(store.get("best", START_BANK)) or START_BANK
  base_bet  = tonumber(store.get("bet", 25)) or 25
  wins      = tonumber(store.get("wins", 0)) or 0
  rounds    = tonumber(store.get("rounds", 0)) or 0

  if bankroll < MIN_BET then bankroll = START_BANK end
  base_bet = clamp(base_bet, MIN_BET, math.min(MAX_BET, bankroll))

  cv = ui.canvas(W, H)
  cv:pos(0, 0)

  build_shoe()
  state = "betting"
  rebuild_buttons()
  draw_screen()
end

function app.on_tick(dt)
  if state ~= "dealer" then
    timer.stop()
    return
  end
  local d_tot = eval_hand(dealer_hand)
  if d_tot < 17 then
    sfx()
    dealer_hand[#dealer_hand + 1] = draw_card()
    draw_screen()
    if eval_hand(dealer_hand) >= 17 then
      settle_round()
    end
  else
    settle_round()
  end
end

function app.on_input(ev)
  if not ev or state == "dealer" then return end

  if ev.type == "down" then
    local ex, ey = tonumber(ev.x) or 0, tonumber(ev.y) or 0
    -- Hit-test bottom bar buttons
    for i = 1, #active_btns do
      local b = active_btns[i]
      if b.x and ex >= b.x and ex <= b.x + b.w and ey >= b.y and ey <= b.y + b.h then
        if b.enabled and b.fn then
          focus_idx = i
          b.fn()
        end
        return
      end
    end
    -- Tap top-right area to toggle sound
    if ey <= 20 and ex >= W - 64 then
      sound_on = not sound_on
      sys.toast(sound_on and "Sound ON" or "Sound OFF")
      draw_screen()
      return
    end
    -- Tap felt after hand finishes to deal immediately
    if state == "done" and ey > 22 and ey < H - 32 then
      start_deal()
      return
    end

  elseif ev.type == "swipe" then
    local d = ev.dir
    if d == "left" then
      cycle_focus(-1)
    elseif d == "right" then
      cycle_focus(1)
    elseif d == "up" then
      if state == "betting" or state == "done" then
        adjust_bet(25)
      elseif state == "player" then
        do_hit()
      end
    elseif d == "down" then
      if state == "betting" or state == "done" then
        adjust_bet(-25)
      elseif state == "player" then
        do_stand()
      end
    end

  elseif ev.type == "key" then
    local k = tostring(ev.key or ""):lower()
    if k == "left" or k == "a" then
      cycle_focus(-1)
    elseif k == "right" or k == "l" then
      cycle_focus(1)
    elseif k == "up" or k == "w" or k == "+" or k == "=" then
      if state == "betting" or state == "done" then
        adjust_bet(10)
      end
    elseif k == "down" or k == "z" or k == "-" then
      if state == "betting" or state == "done" then
        adjust_bet(-10)
      end
    elseif k == "enter" or k == " " then
      trigger_focused()
    elseif k == "m" then
      sound_on = not sound_on
      sys.toast(sound_on and "Sound ON" or "Sound OFF")
      draw_screen()
    elseif state == "player" then
      if k == "h" then do_hit()
      elseif k == "s" then do_stand()
      elseif k == "d" then do_double()
      elseif k == "p" then do_split()
      end
    elseif state == "betting" or state == "done" then
      if k == "d" or k == "h" then start_deal()
      elseif k == "b" and state == "done" then
        state = "betting"
        rebuild_buttons()
        draw_screen()
      elseif k == "c" then
        base_bet = MIN_BET
        draw_screen()
      elseif k == "x" then
        base_bet = math.min(MAX_BET, math.max(MIN_BET, bankroll))
        draw_screen()
      end
    end
  end
end

function app.on_close()
  save_stats()
end

return app
