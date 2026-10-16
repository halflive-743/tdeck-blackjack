-- Standalone Lua 5.4 verification harness for blackjack.lua
-- Mirrors WADAMESH's LuaAppHost.cpp strict integer & instruction-budget checks.

local function checkint(v, what)
  assert(math.tointeger(v) ~= nil, what .. ": expected integer, got " .. tostring(v))
end

local function checkstr(v, what)
  assert(type(v) == "string" or type(v) == "number", what .. ": expected string, got " .. type(v))
end

local storekv = {}
local toasts = {}
local draw_ops = 0
local timer_ms = nil
local rng_seed = 42

local function mock_wada(w, h)
  local cv = { w = w, h = h }
  function cv:fill(col) checkint(col, "fill col"); draw_ops = draw_ops + 1 end
  function cv:rect(x, y, rw, rh, col, filled, radius)
    checkint(x, "rect x"); checkint(y, "rect y")
    checkint(rw, "rect w"); checkint(rh, "rect h"); checkint(col, "rect col")
    if radius ~= nil then checkint(radius, "rect radius") end
    draw_ops = draw_ops + 1
  end
  function cv:line(x1, y1, x2, y2, col, width)
    checkint(x1, "line x1"); checkint(y1, "line y1")
    checkint(x2, "line x2"); checkint(y2, "line y2"); checkint(col, "line col")
    if width ~= nil then checkint(width, "line width") end
    draw_ops = draw_ops + 1
  end
  function cv:circle(x, y, r, col, filled)
    checkint(x, "circle x"); checkint(y, "circle y")
    checkint(r, "circle r"); checkint(col, "circle col")
    draw_ops = draw_ops + 1
  end
  function cv:text(x, y, s, col, size)
    checkint(x, "text x"); checkint(y, "text y")
    checkstr(s, "text s"); checkint(col, "text col")
    if size ~= nil then checkint(size, "text size") end
    draw_ops = draw_ops + 1
  end
  function cv:pos(x, y)
    checkint(x, "pos x"); checkint(y, "pos y")
  end

  return {
    ui = {
      colors = {
        accent = 0x15B6A6, text = 0xE6E9ED, sub = 0x7A7F87,
        bg = 0x000000, panel = 0x15181B, bad = 0xD7574E, good = 0x53C06B
      },
      canvas = function(cw, ch)
        checkint(cw, "canvas w"); checkint(ch, "canvas h")
        assert(cw > 0 and cw <= 480 and ch > 0 and ch <= 480, "canvas bounds")
        return cv
      end,
      text_w = function(str, sz)
        checkstr(str, "text_w str")
        return math.floor(#tostring(str) * ((sz or 12) + 4) * 0.48)
      end,
      text_h = function(sz) return (sz or 12) + 4 end,
    },
    sys = {
      random = function(lo, hi)
        lo = lo or 0; hi = hi or 0
        rng_seed = (rng_seed * 1103515245 + 12345) & 0x7fffffff
        if hi <= lo then return rng_seed end
        return lo + (rng_seed % (hi - lo + 1))
      end,
      toast = function(msg)
        checkstr(msg, "toast")
        toasts[#toasts + 1] = tostring(msg)
      end,
      beep = function() return true end,
      board = function() return { w = w, h = h, touch = true, keyboard = true, trackball = true } end,
      caps = function() return { sdk_ext = true, keyboard = true, touch = true, widget = true } end,
    },
    store = {
      get = function(k, d)
        assert(type(k) == "string")
        if storekv[k] == nil then return d end
        return storekv[k]
      end,
      set = function(k, v)
        assert(type(k) == "string")
        assert(v == nil or type(v) == "string" or type(v) == "number")
        storekv[k] = v
      end,
    },
    timer = {
      every = function(ms) checkint(ms, "timer.every"); timer_ms = ms end,
      stop = function() timer_ms = nil end,
    },
    widget = {
      set = function(t) assert(type(t) == "table"); return true end,
      clear = function() end,
    }
  }
end

-- Run test scenarios on T-Deck (320x208 body) and Heltec V4 (240x244 body)
for _, dims in ipairs({ {320, 208}, {240, 244} }) do
  _G.wada = mock_wada(dims[1], dims[2])
  local app = dofile("blackjack.lua")
  assert(type(app) == "table", "blackjack.lua must return app table")
  app.on_open(dims[1], dims[2])

  -- Play 15 hands exercising bet changes, deal, hit, stand, double, split, and ticks
  for round = 1, 15 do
    app.on_input({ type = "key", key = "+" })
    app.on_input({ type = "key", key = "d" }) -- Deal
    app.on_input({ type = "key", key = "p" }) -- Try split if pair
    app.on_input({ type = "key", key = "h" }) -- Hit
    app.on_input({ type = "key", key = "s" }) -- Stand
    for _ = 1, 8 do
      if timer_ms then app.on_tick(timer_ms) end
    end
  end

  app.on_close()
  assert(type(storekv.bank) == "number", "bankroll must persist as number")
  assert(type(storekv.best) == "number", "best bankroll must persist as number")
  print(string.format("OK %dx%d: draw_ops=%d bank=$%d best=$%d", dims[1], dims[2], draw_ops, storekv.bank, storekv.best))
end
