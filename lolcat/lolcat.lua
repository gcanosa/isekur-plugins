-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- lolcat.lua: the messages in the channels and queries where it's on, in rainbow (or fire, ice, your theme's
-- own colors...), on your screens only: nothing is sent in color, and the logs keep the plain text.
local PATTERNS = {
  rainbow = {0xff0000, 0xff8c00, 0xffff00, 0x00ff00, 0x00ffff, 0x0000ff, 0xa500ff},
  pastel  = {0xff9c9c, 0xffd39c, 0xffff9c, 0x9cff9c, 0x9cffff, 0x9c9cff, 0xff9cff},
  fire    = {0x740000, 0xff0000, 0xff8c00, 0xffff00, 0xff8c00, 0xff0000},
  ice     = {0x0000b5, 0x008cff, 0x00ffff, 0xffffff, 0x00ffff, 0x008cff},
  forest  = {0x007400, 0x00b500, 0x7db500, 0xcfff60, 0x7db500, 0x00b500},
  neon    = {0xff00ff, 0x00ffff, 0xb2ff00, 0xff0098},
  sunset  = {0xff5959, 0xff8c00, 0xffb459, 0xff66ff, 0xa500ff},
}
local NAMES = {"rainbow", "theme", "pastel", "fire", "ice", "forest", "neon", "sunset", "random"}

isekur.setting("lines", "all", "c", "whose messages: everyone's, only yours or only the others'", {"all", "mine", "others"})
isekur.setting("pattern", "rainbow", "c", "the colors; theme: your theme's nick colors", NAMES)
isekur.setting("by", "letters", "c", "a color per letter or per word", {"letters", "words"})
isekur.setting("spread", 2, "c", "letters (or words) per color step; more: a slower gradient")
isekur.setting("shift", true, "c", "each line starts a bit further along the colors, so they flow down the screen like lolcat")

-- mIRC's 99 colors: what a color code can say
local MIRC = {[0] = 0xffffff, 0x000000, 0x00007f, 0x009300, 0xff0000, 0x7f0000, 0x9c009c, 0xfc7f00, 0xffff00,
  0x00fc00, 0x009393, 0x00ffff, 0x0000fc, 0xff00ff, 0x7f7f7f, 0xd2d2d2, 0x470000, 0x472100,
  0x474700, 0x324700, 0x004700, 0x00472c, 0x004747, 0x002747, 0x000047, 0x2e0047, 0x470047,
  0x47002a, 0x740000, 0x743a00, 0x747400, 0x517400, 0x007400, 0x007449, 0x007474, 0x004074,
  0x000074, 0x4b0074, 0x740074, 0x740045, 0xb50000, 0xb56300, 0xb5b500, 0x7db500, 0x00b500,
  0x00b571, 0x00b5b5, 0x0063b5, 0x0000b5, 0x7500b5, 0xb500b5, 0xb5006b, 0xff0000, 0xff8c00,
  0xffff00, 0xb2ff00, 0x00ff00, 0x00ffa0, 0x00ffff, 0x008cff, 0x0000ff, 0xa500ff, 0xff00ff,
  0xff0098, 0xff5959, 0xffb459, 0xffff71, 0xcfff60, 0x6fff6f, 0x65ffc9, 0x6dffff, 0x59b4ff,
  0x5959ff, 0xc459ff, 0xff66ff, 0xff59bc, 0xff9c9c, 0xffd39c, 0xffff9c, 0xe2ff9c, 0x9cff9c,
  0x9cffdb, 0x9cffff, 0x9cd3ff, 0x9c9cff, 0xdc9cff, 0xff9cff, 0xff94d3}  -- 88-98 are grays: never picked

local function rgb(c) return c >> 16 & 255, c >> 8 & 255, c & 255 end
local near = {}
local function nearest(c)
  if near[c] then return near[c] end
  local r, g, b = rgb(c)
  local best, bd = 0, math.huge
  for i = 0, 87 do
    local R, G, B = rgb(MIRC[i])
    local d = 2 * (R - r) ^ 2 + 4 * (G - g) ^ 2 + 3 * (B - b) ^ 2
    if d < bd then best, bd = i, d end
  end
  near[c] = best
  return best
end

local function mix(a, b, t)
  local r1, g1, b1 = rgb(a)
  local r2, g2, b2 = rgb(b)
  local f = function(x, y) return math.floor(x + (y - x) * t + 0.5) end
  return f(r1, r2) << 16 | f(g1, g2) << 8 | f(b1, b2)
end

-- the pattern's colors, fitted to the theme: on a light background the bright ones are darkened so they read
local function stops(name)
  local th = isekur.theme()
  if name == "random" then name = NAMES[math.random(#NAMES - 1)] end
  local s = PATTERNS[name]
  if name == "theme" then
    s = #th.nicks > 1 and th.nicks or nil
    if not s and th.fg and th.hilight and th.fg ~= th.hilight then s = {th.fg, th.hilight} end
    s = s or PATTERNS.rainbow
  end
  if th.bg and name ~= "theme" then  -- the theme's own colors are made for its background already
    local r, g, b = rgb(th.bg)
    if (r * 299 + g * 587 + b * 114) / 1000 > 140 then
      local d = {}
      for i, c in ipairs(s) do d[i] = mix(c, 0, 0.3) end
      s = d
    end
  end
  return s
end

-- text with a color code before each letter (or word) whose color changed; its own colors give way
local row = 0
local function paint(text, srv, target, pattern)
  text = text:gsub("\3%d?%d?,%d%d?", ""):gsub("\3%d?%d?", ""):gsub("\4%x%x%x%x%x%x,%x%x%x%x%x%x", ""):gsub("\4%x?%x?%x?%x?%x?%x?", "")
  local s = stops(pattern or isekur.opt("pattern", srv, target))
  local spread = math.max(1, isekur.opt("spread", srv, target))
  local words = isekur.opt("by", srv, target) == "words"
  row = row + 1
  local pos = isekur.opt("shift", srv, target) and row * 0.5 % #s or 0
  local out, last, inword = {}, nil, false
  local function color()
    local i = math.floor(pos) % #s
    local code = nearest(mix(s[i + 1], s[(i + 1) % #s + 1], pos - math.floor(pos)))
    if code ~= last then out[#out + 1] = string.format("\3%02d", code); last = code end
    pos = pos + 1 / spread
  end
  local function chunk(t)
    for _, cp in utf8.codes(t) do
      local ch = utf8.char(cp)
      local blank = ch:match("^%s$") ~= nil
      if cp < 32 then  -- bold, italics...: no color of their own
      elseif not blank and ch ~= "," and (not words or not inword) then color() end  -- no code before a comma: it'd read as a background
      if cp >= 32 then inword = not blank end
      out[#out + 1] = ch
    end
  end
  local ok = pcall(function()
    local at = 1
    while true do
      local a, b = text:find("%a[%w+.-]*://[^%s\1-\31]+", at)
      local c, d = (" " .. text):find("%s[#&][^%s,\1-\31]+", at)  -- a #channel at a word's start (c: its # in text)
      if d then d = d - 1 end
      if c and (not a or c < a) then a, b = c, d end
      chunk(text:sub(at, (a or 0) - 1))
      if not a then break end
      color(); inword = true  -- a link or a channel in one color: the webchat links one color run at a time
      out[#out + 1] = text:sub(a, b)
      at = b + 1
    end
  end)
  return ok and table.concat(out) .. "\15" or nil  -- not UTF-8: as it came
end

isekur.on("show", function(e)
  local who = isekur.opt("lines", e.srv, e.target)
  if who == "all" or (who == "mine") == e.self then return paint(e.text, e.srv, e.target) end
end)

isekur.command("lolcat", "", function(args, srv, target)  -- each pattern, here only
  for _, n in ipairs(NAMES) do
    if n ~= "random" then
      isekur.print(srv, target, string.format("%-8s ", n) .. paint("the quick brown fox jumps over the lazy cat", srv, target, n))
    end
  end
end)
