-- Standalone Lua 5.4 verification harness for blackjack.lua
-- Mirrors WADAMESH's LuaAppHost.cpp strict integer, 1..480 canvas bounds, & instruction-budget checks.

local function checkint(v, what)
  assert(math.tointeger(v) ~= nil, what .. ": expected integer, got " .. tostring(v))
end

local function checkstr(v, what)
  assert(type(v) == "string" or type(v) == "number", what .. ": expected string, got " .. type(v))
end

local storekv = {}
local toasts = {}
local draw_ops = 0
local canvases = {}
local timer_ms = nil
local rng_seed = 42

local function mock_wada(w, h)
  canvases = {}
  draw_ops = 0

  return {
    ui = {
      colors = {
        accent = 0x15B6A6, text = 0xE6E9ED, sub = 0x7A7F87,
        bg = 0x000000, panel = 0x15181B, bad = 0xD7574E, good = 0x53C06B
      },
      canvas = function(cw, ch)
        checkint(cw, "canvas w"); checkint(ch, "canvas h")
        assert(cw > 0 and cw <= 480 and ch > 0 and ch <= 480,
          string.format("FATAL: canvas(%s, %s) exceeds LuaAppHost 1..480 bounds!", tostring(cw), tostring(ch)))
        local cv = { w = cw, h = ch, x = 0, y = 0 }
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
          cv.x, cv.y = x, y
        end
        canvases[#canvases + 1] = cv
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
      board = function()
        local b = { w = w, h = h, touch = true, keyboard = true, trackball = true }
        if w == 240 and (h == 244 or h == 320) then
          b.name = "ThinkNode M9"
          b.model = "Elecrow ThinkNode M9"
          b.touch = false
        end
        return b
      end,
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

-- Verify that the created canvas tiles cover the entire WxH screen with no gaps
local function verify_canvas_coverage(w, h)
  assert(#canvases >= 1, "at least 1 canvas must be created")
  local area = 0
  local max_x, max_y = 0, 0
  for _, c in ipairs(canvases) do
    assert(c.x >= 0 and c.y >= 0, "canvas tile position must be non-negative")
    assert(c.x + c.w <= w and c.y + c.h <= h, "canvas tile must not exceed screen bounds")
    area = area + (c.w * c.h)
    if c.x + c.w > max_x then max_x = c.x + c.w end
    if c.y + c.h > max_y then max_y = c.y + c.h end
  end
  assert(max_x == w and max_y == h and area == w * h,
    string.format("canvas tiles must cover exact %dx%d screen (got max=%dx%d area=%d)", w, h, max_x, max_y, area))
end

local devices = {
  { name = "LilyGo T-Deck",                   w = 320,  h = 208  },
  { name = "ThinkNode M9",                    w = 240,  h = 244  },
  { name = "ThinkNode M9 (Full 240x320)",     w = 240,  h = 320  },
  { name = "LilyGo T-LoRa Pager",             w = 480,  h = 178  },
  { name = "LilyGo T-Display P4 Compact (Port)", w = 270, h = 551 },
  { name = "LilyGo T-Display P4 LCD (Port)",  w = 540,  h = 1102 },
  { name = "LilyGo T-Display P4 LCD (Land)",  w = 1168, h = 474  },
  { name = "LilyGo T-Display P4 AMOLED (Port)", w = 568, h = 1166 },
  { name = "LilyGo T-Display P4 AMOLED (Land)", w = 1232, h = 502 },
}

for _, dev in ipairs(devices) do
  _G.wada = mock_wada(dev.w, dev.h)
  local app = dofile("blackjack.lua")
  assert(type(app) == "table", "blackjack.lua must return app table")

  local max_instr = 0
  local function guarded_call(fn, ...)
    local instr = 0
    debug.sethook(function() instr = instr + 1000 end, "", 1000)
    local ok, err = pcall(fn, ...)
    debug.sethook()
    assert(ok, err)
    if instr > max_instr then max_instr = instr end
    assert(instr < 100000, string.format("instruction budget exceeded (%d >= 100000) on %s", instr, dev.name))
  end

  guarded_call(app.on_open, dev.w, dev.h)
  verify_canvas_coverage(dev.w, dev.h)

  -- Play 15 hands exercising bet changes, deal, hit, stand, double, split, touch taps, and ticks
  for round = 1, 15 do
    guarded_call(app.on_input, { type = "key", key = "+" })
    if round % 2 == 1 then
      guarded_call(app.on_input, { type = "down", x = dev.w - 20, y = dev.h - 15 })
    else
      guarded_call(app.on_input, { type = "key", key = "d" })
    end
    guarded_call(app.on_input, { type = "key", key = "p" }) -- Try split if pair
    guarded_call(app.on_input, { type = "key", key = "h" }) -- Hit
    guarded_call(app.on_input, { type = "key", key = "s" }) -- Stand
    for _ = 1, 8 do
      if timer_ms then guarded_call(app.on_tick, timer_ms) end
    end
  end

  guarded_call(app.on_close)
  assert(type(storekv.bank) == "number", "bankroll must persist as number")
  assert(type(storekv.best) == "number", "best bankroll must persist as number")
  print(string.format("OK %-34s (%4dx%-4d): tiles=%d max_instr=%5d draw_ops=%5d bank=$%d",
    dev.name, dev.w, dev.h, #canvases, max_instr, draw_ops, storekv.bank))
end
