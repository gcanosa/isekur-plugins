-- version: 1.1
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- screensaver: after `idle` minutes without a key, click or mouse move, the terminal and the webchat
-- show digital rain, floating particles or a quiet sky of drifting stars until you touch something;
-- with lock on, waking asks for the lock password. /screensaver [matrix|particles|stars] starts one now.
isekur.setting("idle", 10, "g", "minutes without a key, click or mouse move (terminal or webchat); 0: only /screensaver")
isekur.setting("saver", "random", "g", "which one; random: another each time", {"random", "matrix", "particles", "stars"})
isekur.setting("lock", false, "g", "waking asks for the lock password (the one /lock sets)")

local function rgb(r, g, b) return math.floor(r) * 65536 + math.floor(g) * 256 + math.floor(b) end
local function scale(c, k)  -- a 0xRRGGBB color at k (0..1) of its brightness
  return rgb((c >> 16 & 255) * k, (c >> 8 & 255) * k, (c & 255) * k)
end
local rnd = math.random

-- each saver: new(w, h) gives its state, draw(s, w, h, t, dt) moves it on by dt seconds and puts the frame
local savers = {}

-- digital rain: a drop per column falls at its own speed, a bright head and a trail fading to dark green
local KANA = {}
for cp = 0xFF66, 0xFF9D do KANA[#KANA + 1] = utf8.char(cp) end
for d = 0, 9 do KANA[#KANA + 1] = tostring(d) end
local function glyph() return KANA[rnd(#KANA)] end
local SHADES = {}
for i = 1, 5 do SHADES[i] = scale(0x00FF46, (1 - (i - 1) / 5) ^ 1.5 * 0.9 + 0.1) end
local function drop(h, top)
  return {y = top and -rnd(0, h * 2) or 0, speed = rnd(8, 24), len = rnd(4, math.max(5, h // 2)), cells = {}}
end
savers.matrix = {
  new = function(w, h)
    local s = {}
    for x = 0, w - 1 do s[x] = drop(h, true) end
    return s
  end,
  draw = function(s, w, h, t, dt)
    for x = 0, w - 1 do
      local d = s[x]
      d.y = d.y + d.speed * dt
      local head = math.floor(d.y)
      if head - d.len > h then s[x] = drop(h, true); d = s[x]; head = math.floor(d.y) end
      for i = 0, d.len do
        local y = head - i
        if y >= 0 and y < h then
          if not d.cells[y] or rnd() < 0.02 then d.cells[y] = glyph() end
          -- 5 shades, not a smooth fade: most of a trail stays the same color as it falls, so the webchat gets fewer cells a frame
          local col = i == 0 and 0xD8FFD8 or SHADES[math.min(5, 1 + (i * 5) // (d.len + 1))]
          isekur.put(x, y, d.cells[y], col)
        end
      end
    end
  end,
}

-- floating particles: soft colored motes drifting and pulsing, wrapping round the edges
local HUES = {0x5CE1E6, 0xB388FF, 0xFF80BF, 0xFFD166, 0x7CF5B0}
savers.particles = {
  new = function(w, h)
    local s = {}
    for i = 1, math.max(20, math.min(160, w * h // 60)) do
      local a = rnd() * 2 * math.pi
      s[i] = {x = rnd() * w, y = rnd() * h, vx = math.cos(a) * (0.5 + rnd() * 2), vy = math.sin(a) * (0.25 + rnd()),
              ph = rnd() * 6.3, sp = 0.6 + rnd() * 1.4, c = HUES[rnd(#HUES)]}
    end
    return s
  end,
  draw = function(s, w, h, t, dt)
    for _, p in ipairs(s) do
      p.x = (p.x + (p.vx + math.sin(t * 0.4 + p.ph) * 0.6) * dt) % w
      p.y = (p.y + (p.vy + math.cos(t * 0.3 + p.ph) * 0.3) * dt) % h
      local k = math.floor(8 * (0.55 + 0.45 * math.sin(t * p.sp + p.ph)) + 0.5) / 8  -- in steps: fewer cells change a frame
      isekur.put((p.x - p.vx * 0.6) % w, (p.y - p.vy * 0.6) % h, "·", scale(p.c, k * 0.35))  -- fractions: the webchat draws between cells
      isekur.put(p.x, p.y, k > 0.75 and "•" or k > 0.4 and "∙" or "·", scale(p.c, k))
    end
  end,
}

-- a quiet sky: three layers of stars drifting left, the near ones faster, twinkling; now and then a shooting star
local LAYERS = {
  {n = 1 / 45, speed = 0.25, c = 0x56607E, ch = {".", "·"}},
  {n = 1 / 110, speed = 0.7, c = 0xA4AECB, ch = {"·", "+"}},
  {n = 1 / 300, speed = 1.5, c = 0xEEF1FF, ch = {"*", "✦"}},
}
savers.stars = {
  new = function(w, h)
    local s = {stars = {}, next = 6 + rnd() * 10}
    for li, l in ipairs(LAYERS) do
      for _ = 1, math.max(3, math.floor(w * h * l.n)) do
        s.stars[#s.stars + 1] = {x = rnd() * w, y = rnd(0, h - 1), l = li, ph = rnd() * 6.3, ch = l.ch[rnd(#l.ch)]}
      end
    end
    return s
  end,
  draw = function(s, w, h, t, dt)
    for _, st in ipairs(s.stars) do
      local l = LAYERS[st.l]
      st.x = st.x - l.speed * dt
      if st.x < 0 then st.x, st.y = st.x + w, rnd(0, h - 1) end
      isekur.put(st.x, st.y, st.ch, scale(l.c, 0.7 + math.floor(3 * math.sin(t * 1.3 + st.ph) + 0.5) / 10))
    end
    local m = s.meteor
    if not m and t >= s.next then
      m = {x = rnd(w // 4, w - 1), y = rnd(0, h // 3), vx = -(w / 2 + rnd() * w / 3), vy = h / 4 + rnd() * h / 6}
      s.meteor = m
    end
    if m then
      m.x, m.y = m.x + m.vx * dt, m.y + m.vy * dt
      for i = 0, 7 do
        local k = i / 8
        isekur.put(m.x - m.vx * k * 0.12, m.y - m.vy * k * 0.12, i == 0 and "*" or "·", scale(0xFFF4D6, 1 - k))
      end
      if m.x < -8 or m.y > h + 4 then s.meteor, s.next = nil, t + 8 + rnd() * 14 end
    end
  end,
}

local NAMES = {"matrix", "particles", "stars"}
local FPS = {matrix = 15, particles = 30, stars = 30}
local warned = false

local function start(name)
  if name == "random" or not savers[name] then name = NAMES[rnd(#NAMES)] end
  local saver, st = savers[name], {}  -- st[ui]: the terminal and the webchat each at their own size
  local on = isekur.screen(function(e)
    local s, t = st[e.ui], e.t / 1000
    if not s or s.w ~= e.w or s.h ~= e.h then
      s = {w = e.w, h = e.h, t = t, data = saver.new(e.w, e.h)}
      st[e.ui] = s
    end
    local dt = math.min(0.2, math.max(0, t - s.t))
    s.t = t
    saver.draw(s.data, e.w, e.h, t, dt)
  end, FPS[name])
  if not on then return false end  -- nobody at a terminal or a webchat: iSekur doesn't start one
  if isekur.opt("lock") and not isekur.lock() and not warned then
    warned = true
    isekur.print(nil, nil, "lock is on, but there's no lock password yet: /lock sets one", true)
  end
  return true
end

isekur.command("screensaver", "[matrix|particles|stars]", function(args)
  args = args:lower():match("^%s*(%S*)")
  if args ~= "" and args ~= "random" and not savers[args] then return "No such screensaver: " .. args .. " (matrix, particles, stars)" end
  if not start(args ~= "" and args or isekur.opt("saver")) then return "No terminal or webchat attached to show it on" end
end)

isekur.on("tick", function()
  if isekur.screen() then return end
  local idle = isekur.opt("idle")
  if idle > 0 and isekur.inactive() >= idle * 60 then start(isekur.opt("saver")) end
end)
