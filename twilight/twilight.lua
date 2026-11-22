-- version: 1.1
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- twilight: warms the colors after dark, like f.lux or Night Shift, in the terminal and the webchat and whatever the theme. Night is
-- sunset to sunrise where YOU are (a city or coordinates: iSekur on a server in another country still follows your sun) or hours you pick.
-- It changes over minutes, and switching it on or off, or by hand, takes a minute too: the screen never jumps in a dark room.
-- /twilight opens its window (Preview sweeps day to night and back, a few seconds each way); /twilight preview does the same from the keyboard.
-- The location goes to open-meteo.com (a city's coordinates, then the sun's times); nothing else leaves this machine.

isekur.setting("mode", "sun", "g", "when it is night: sun (sunset to sunrise there), schedule (start to end) or always", {"sun", "schedule", "always"})
isekur.setting("location", "", "g", "where YOU are: a city (Berlin, Springfield US) or latitude,longitude. Not where iSekur runs")
isekur.setting("start", "21:00", "g", "schedule: night starts (HH:MM, the clock where you are); also used until the sun's times arrive")
isekur.setting("end", "07:00", "g", "schedule: night ends (HH:MM)")
isekur.setting("utc_offset", "", "g", "hours from UTC where you are (-3, 5.5) with no location; empty: the location's, else this machine's")
isekur.setting("day", 6500, "g", "color temperature by day, in kelvin: 6500 leaves the colors alone", nil)
isekur.setting("night", 3400, "g", "color temperature at night, in kelvin: 3400 warm, 2700 warmer, 1900 candle light (1000 to 6500)")
isekur.setting("dim", 0, "g", "extra darkening at night, in percent (0 to 60)")
isekur.setting("ramp", 60, "g", "minutes the change takes around sunset and sunrise (the middle is the sunset); 0: at once")
isekur.setting("fade", 60, "g", "seconds that switching it on or off, a manual change or the end of a pause takes: never a jump (0 to 600)")
isekur.setting("where", "both", "g", "which screens are tinted", {"both", "terminal", "web"})
isekur.setting("media", true, "g", "tint the webchat's pictures and videos (the preview plugin's) too; off to see a picture's real colors")

local S = {n = 0, why = "day", said = {}, big = true}  -- n: 0 day to 1 night as of the last update; big: the next change takes `fade`

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function note(text) isekur.print(nil, nil, text, true) end
local function hint_once(key, text) if not S.said[key] then S.said[key] = true; note(text) end end
local function pack(...) return {...} end
local function mins(s)
  local h, m = tostring(s):match("^%s*(%d%d?):(%d%d)%s*$")
  h, m = tonumber(h), tonumber(m)
  if h and m and h < 24 and m < 60 then return h * 60 + m end
end

-- kelvin to the multiplier of each channel (Tanner Helland's fit of a black body), 6500 K = no change
local function raw(K)
  local t = K / 100
  local r = t <= 66 and 255 or 329.698727446 * (t - 60) ^ -0.1332047592
  local g = t <= 66 and 99.4708025861 * math.log(t) - 161.1195681661 or 288.1221695283 * (t - 60) ^ -0.0755148492
  local b = t >= 66 and 255 or t <= 19 and 0 or 138.5177312231 * math.log(t - 10) - 305.0447927307
  return r, g, b
end
local R0, G0, B0 = raw(6500)
local function mult(K)
  local r, g, b = raw(clamp(K, 1000, 6500))
  return math.min(1, r / R0), math.min(1, g / G0), math.min(1, b / B0)
end
local function dimv() return clamp(isekur.opt("dim"), 0, 60) / 100 end
-- n: 0 day .. 1 night -> r, g, b, dim (the temperature moves in a straight line between the two settings)
local function look(n)
  local day, night = clamp(isekur.opt("day"), 1000, 6500), clamp(isekur.opt("night"), 1000, 6500)
  local r, g, b = mult(day + (night - day) * n)
  return r, g, b, dimv() * n
end

-- time: seconds east of UTC where you are: utc_offset, else the location's (from the sun's data), else this machine's
local function host_off(t)
  local sg, h, m = isekur.date(t, "%z"):match("^([+-])(%d%d)(%d%d)$")
  if not sg then return 0 end
  return (sg == "-" and -1 or 1) * (tonumber(h) * 3600 + tonumber(m) * 60)
end

-- the location setting: latitude, longitude, a label; nil, nil, nil, "a city" when it has to be looked up first
local function place()
  local loc = isekur.opt("location"):match("^%s*(.-)%s*$")
  if loc == "" then return end
  local la, lo = loc:match("^(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)$")
  la, lo = tonumber(la), tonumber(lo)
  if la and lo then
    if math.abs(la) <= 90 and math.abs(lo) <= 180 then return la, lo, ("%.2f, %.2f"):format(la, lo) end
    return
  end
  if S.geo and S.geo.q == loc:lower() then return S.geo.lat, S.geo.lon, S.geo.label end
  return nil, nil, nil, loc
end
local function key_of(la, lo) return ("%.3f,%.3f"):format(la, lo) end

local function off_at(t)
  local o = tonumber(isekur.opt("utc_offset"))
  if o then return math.floor(clamp(o, -14, 14) * 3600) end
  local la, lo = place()
  if la and S.off and S.sun_key == key_of(la, lo) then return S.off end
  return host_off(t)
end
local function clock(t) return isekur.date(t + off_at(t) - host_off(t), "%H:%M") end  -- t as the clock of where you are
local function span(s)
  local m = math.max(1, math.floor(s / 60 + 0.5))
  return m >= 60 and ("%dh%02dm"):format(m // 60, m % 60) or m .. "m"
end

-- ---- the sun: the location's coordinates (geocoding), then its sunrises and sunsets (Open-Meteo, no key) ----------------------------------
local function enc(s) return (s:gsub("[^%w%-_.~]", function(c) return ("%%%02X"):format(c:byte()) end)) end

local function geocode(loc)
  if S.geo_busy or (S.geo_retry and isekur.time() < S.geo_retry) then return end
  local name, cc = loc:match("^(.-)%s*,%s*(%a%a)$")  -- "Springfield, US": the country narrows it
  local url = "https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name=" .. enc(name or loc) .. (cc and "&countryCode=" .. cc:upper() or "")
  S.geo_busy = true
  local ok = isekur.http(url, function(r)
    S.geo_busy = false
    local la, lo = tonumber((r.body:match('"latitude":(-?[%d%.]+)'))), tonumber((r.body:match('"longitude":(-?[%d%.]+)')))
    if r.status == 200 and la and lo then
      local nm, co = r.body:match('"name":"(.-)"'), r.body:match('"country":"(.-)"')
      S.geo = {q = loc:lower(), lat = la, lon = lo, label = ((nm or loc) .. (co and ", " .. co or "")):gsub("[%c]", " ")}
      isekur.store_set("geo", ("%s\t%s\t%s\t%s"):format(S.geo.q, la, lo, S.geo.label))
      S.force = true
      note("location: " .. S.geo.label .. " (" .. ("%.2f, %.2f"):format(la, lo) .. ")")
    else
      S.geo_retry = isekur.time() + 600
      hint_once("geo" .. loc, r.status == 200 and ("no place called " .. loc .. ": try a bigger city, or latitude,longitude") or "can't reach the location service (open-meteo.com): trying again in 10 minutes")
    end
  end)
  if not ok then S.geo_busy = false end
end

local function sun_set(key, off, rises, sets, at)
  local ev = {}
  for v in rises:gmatch("[^,]+") do local n = tonumber(v); if n then ev[#ev + 1] = {t = n, night = false} end end
  for v in sets:gmatch("[^,]+") do local n = tonumber(v); if n then ev[#ev + 1] = {t = n, night = true} end end
  table.sort(ev, function(a, b) return a.t < b.t end)
  S.ev, S.sun_key, S.off, S.sun_at = ev, key, off, at or isekur.time()
  if not at then isekur.store_set("sun", table.concat({key, S.sun_at, off, rises, sets}, "|")) end
end

local function sun_fetch(la, lo)
  local t, key = isekur.time(), key_of(la, lo)
  if S.sun_key == key and t - (S.sun_at or 0) < 6 * 3600 then return end
  if S.sun_busy or (S.sun_retry and t < S.sun_retry) then return end
  S.sun_busy = true
  local url = ("https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&daily=sunrise,sunset&timezone=auto&past_days=1&forecast_days=3&timeformat=unixtime"):format(la, lo)
  local ok = isekur.http(url, function(r)
    S.sun_busy = false
    local off = tonumber(r.body:match('"utc_offset_seconds":(-?%d+)'))
    local rises, sets = r.body:match('"sunrise":%[([^%]]*)%]'), r.body:match('"sunset":%[([^%]]*)%]')
    if r.status == 200 and off and rises and sets then
      sun_set(key, off, rises, sets)
      S.force = true
    else
      S.sun_retry = isekur.time() + 600
      hint_once("sun", "can't get the sun's times (open-meteo.com): using the hours " .. isekur.opt("start") .. "-" .. isekur.opt("end") .. " meanwhile")
    end
  end)
  if not ok then S.sun_busy = false end
end

-- ---- when it is night ---------------------------------------------------------------------------------------------------------------------
-- the sunrises and sunsets (or the schedule's start and end) around t: {t, night = true from then on}
local function events(t)
  local la, lo = place()
  if isekur.opt("mode") == "sun" and la and S.ev and #S.ev > 1 and S.sun_key == key_of(la, lo) and t >= S.ev[1].t and t < S.ev[#S.ev].t then return S.ev end
  local a, b = mins(isekur.opt("start")) or 21 * 60, mins(isekur.opt("end")) or 7 * 60
  local day0 = (t + off_at(t)) // 86400 * 86400 - off_at(t)  -- your midnight
  local ev = {}
  for d = -1, 2 do
    ev[#ev + 1] = {t = day0 + d * 86400 + a * 60, night = true}
    ev[#ev + 1] = {t = day0 + d * 86400 + b * 60, night = false}
  end
  table.sort(ev, function(x, y) return x.t < y.t end)
  return ev
end

-- 0 (day) to 1 (night): the state since the last event, and inside the ramp around the nearest one a smooth move to the other
local function night_at(t)
  local half = clamp(isekur.opt("ramp"), 0, 240) * 30
  local last, near, nd
  for _, e in ipairs(events(t)) do
    if e.t <= t then last = e end
    local d = math.abs(t - e.t)
    if not nd or d < nd then near, nd = e, d end
  end
  if not last then return 0 end
  if near and nd < half then
    local f = (t - (near.t - half)) / (2 * half)
    f = f * f * (3 - 2 * f)
    return near.night and f or 1 - f
  end
  return last.night and 1 or 0
end

local function target(t)  -- r, g, b, dim now
  if S.pause then
    if t < S.pause then S.why, S.n = "paused", 0; return 1, 1, 1, 0 end
    S.pause, S.big = nil, true  -- back from a pause: it takes `fade`
  end
  if S.hold then
    S.why = S.hold.dark and "darkroom" or "manual"
    if S.hold.dark then S.n = 1; return 1, 0, 0, dimv() end
    S.n = clamp((6500 - S.hold.k) / 4600, 0, 1)
    local r, g, b = mult(S.hold.k)
    return r, g, b, dimv()
  end
  S.n = isekur.opt("mode") == "always" and 1 or night_at(t)
  S.why = S.n >= 0.999 and "night" or S.n <= 0.001 and "day" or "ramp"
  return look(S.n)
end

-- ---- applying it: core glides to it (isekur.tint's fade), and glides back to none when the plugin goes ----------------------------------------
local function neutral(c) return c[1] >= 0.999 and c[2] >= 0.999 and c[3] >= 0.999 and c[4] <= 0.001 end
local function apply(r, g, b, d, secs)
  local w = isekur.opt("where")
  isekur.tint{r = r, g = g, b = b, dim = d, term = w ~= "web", web = w ~= "terminal", media = isekur.opt("media"), fade = secs, out = clamp(isekur.opt("fade"), 0, 600)}
  S.cur = {r, g, b, d}
end

local function update(t)
  S.force = nil
  local la, lo, _, need = place()
  if need then geocode(need) elseif la and isekur.opt("mode") == "sun" then sun_fetch(la, lo) end
  if isekur.opt("mode") == "sun" and not la and not need and isekur.opt("location") == "" then
    hint_once("noloc", "no location yet, so the hours " .. isekur.opt("start") .. "-" .. isekur.opt("end") .. " on this machine's clock. If iSekur runs on a server, tell it where YOU are: /twilight location <city>")
  elseif isekur.opt("mode") == "schedule" and not la and not tonumber(isekur.opt("utc_offset")) then
    hint_once("tz", "the schedule follows this machine's clock. If iSekur runs on a server elsewhere, set where you are: /twilight location <city>")
  end
  local r, g, b, d = target(t)
  local fade = clamp(isekur.opt("fade"), 0, 600)
  local big = S.big
  S.big = false
  local c = S.cur
  if not c and r >= 0.999 and g >= 0.999 and b >= 0.999 and d <= 0.001 and not big then return end  -- by day, nothing is held
  if big or not c or math.abs(c[1] - r) + math.abs(c[2] - g) + math.abs(c[3] - b) + math.abs(c[4] - d) >= 0.004 then
    apply(r, g, b, d, big and fade or math.min(10, fade))  -- a slow ramp: a small step now and then; anything you asked for: the whole fade
  end
end

-- ---- the preview: day, night, back to now, a few seconds each way --------------------------------------------------------------------------
local function start_preview(sec)
  sec = math.floor(clamp(sec or 4, 2, 20))
  local steps = {}
  if S.cur and not neutral(S.cur) then steps[#steps + 1] = {tint = pack(look(0)), n = 0, fade = sec, wait = sec} end
  steps[#steps + 1] = {tint = pack(look(1)), n = 1, fade = sec, wait = sec + 1}
  steps[#steps + 1] = {live = true, fade = sec, wait = sec}
  S.pv = {steps = steps, i = 0, at = 0}
end
local function pv_step(t)
  local pv = S.pv
  pv.i = pv.i + 1
  local s = pv.steps[pv.i]
  if not s then S.pv = nil; return end
  local c = s.live and pack(target(t)) or s.tint
  if s.n then S.n = s.n end
  apply(c[1], c[2], c[3], c[4], s.fade)
  pv.at = t + s.wait
end

-- ---- what it says about itself ---------------------------------------------------------------------------------------------------------------
local function describe(t)
  local day, night = clamp(isekur.opt("day"), 1000, 6500), clamp(isekur.opt("night"), 1000, 6500)
  local K = math.floor(day + (night - day) * S.n + 0.5)
  local l1 = S.pv and "Preview: day to night and back"
    or S.why == "paused" and ("Off for %s more"):format(span(S.pause - t))
    or S.why == "darkroom" and "Darkroom: red only"
    or S.why == "manual" and ("Manual: %d K"):format(S.hold.k)
    or S.why == "night" and ("Night: %d K%s"):format(K, dimv() > 0 and (", %d%% dimmer"):format(math.floor(dimv() * 100)) or "")
    or S.why == "ramp" and ("Changing: %d K"):format(K) or "Day: no tint"
  local la, lo, label = place()
  local mode = isekur.opt("mode")
  local l2 = mode == "always" and "Always night"
    or mode == "sun" and la and ("Sun at %s"):format(label)
    or ("Hours %s-%s, the clock of %s"):format(isekur.opt("start"), isekur.opt("end"), la and label or tonumber(isekur.opt("utc_offset")) and "UTC+" .. isekur.opt("utc_offset") or "this machine")
  local l3 = "No change coming"
  if mode ~= "always" then
    for _, e in ipairs(events(t)) do
      if e.t > t then l3 = ("Next: %s at %s, in %s"):format(e.night and "night" or "day", clock(e.t), span(e.t - t)); break end
    end
  end
  return {l1, l2, l3, "preview, off [min], auto, <kelvin>, location <city>"}
end

local function show_window()
  local t = isekur.time()
  isekur.window{title = "Twilight", display = describe(t), sky = S.n, buttons = {"Preview", S.pause and "Resume" or "Off 1h", "Close"}}
end

-- the plugin manager's page for twilight (/plugin, Configure): where it is now, a sun and a moon, and Preview and Off 1h, so the settings can be tried
-- as they are changed. isekur.panel came with API 15 after tint: an older build of it has no panel, only the window and the commands
local function publish_panel(t)
  local d = describe(t)
  isekur.panel{lines = {d[1], d[2], d[3]}, sky = S.n, actions = {{"Preview", "/twilight preview"}, S.pause and {"Resume", "/twilight auto"} or {"Off 1h", "/twilight off 60"}}}
end

isekur.on("window", function(e)
  if e.action ~= "button" then return end
  if e.button == "Preview" then start_preview()
  elseif e.button == "Off 1h" then S.pause, S.hold, S.big = isekur.time() + 3600, nil, true
  elseif e.button == "Resume" then S.pause, S.hold, S.big = nil, nil, true
  else isekur.window(false) end
end)

isekur.command("twilight", "[status | preview [seconds] | <kelvin> | darkroom | off [minutes] | auto | location <city | lat,lon>]", function(args, srv, target)
  local a, rest = args:match("^%s*(%S*)%s*(.-)%s*$")
  a = a:lower()
  local function say(text) isekur.print(srv, target, text, true) end
  if a == "" then show_window()
  elseif a == "status" then for _, l in ipairs(describe(isekur.time())) do say(l) end
  elseif a == "preview" then start_preview(tonumber(rest)); say("preview: day to night and back")
  elseif a == "darkroom" then S.hold, S.pause, S.big = {dark = true}, nil, true
  elseif a == "off" then S.pause, S.hold, S.big = isekur.time() + math.floor(clamp(tonumber(rest) or 60, 1, 1440)) * 60, nil, true
  elseif a == "auto" or a == "resume" then S.hold, S.pause, S.big = nil, nil, true
  elseif a == "location" then
    if rest == "" then return "Usage: /twilight location <city | latitude,longitude>" end
    isekur.set("location", rest)
    S.sun_key = nil
    S.said = {}
    say("location: " .. rest)
  elseif tonumber(a) then
    S.hold, S.pause, S.big = {k = clamp(tonumber(a), 1000, 6500)}, nil, true
  else return "Usage: /twilight [status | preview [seconds] | <kelvin> | darkroom | off [minutes] | auto | location <city | lat,lon>]" end
end)

-- ---- running ---------------------------------------------------------------------------------------------------------------------------------
local function sig()
  local o = {}
  for _, k in ipairs({"mode", "location", "start", "end", "utc_offset", "day", "night", "dim", "ramp", "fade", "where", "media"}) do o[#o + 1] = tostring(isekur.opt(k)) end
  return table.concat(o, "|")
end

do  -- what was found last time: no wait for the network after a restart
  local q, la, lo, label = (isekur.store_get("geo") or ""):match("^(.-)\t(.-)\t(.-)\t(.*)$")
  if q and tonumber(la) and tonumber(lo) then S.geo = {q = q, lat = tonumber(la), lon = tonumber(lo), label = label} end
  local k, at, off, rs, ss = (isekur.store_get("sun") or ""):match("^(.-)|(%d+)|(-?%d+)|(.-)|(.*)$")
  if k then sun_set(k, tonumber(off), rs, ss, tonumber(at)) end
  S.sig = sig()
end

isekur.on("tick", function()
  local t = isekur.time()
  if S.pv then
    if t >= S.pv.at then pv_step(t) end
  else
    local sg = sig()
    if sg ~= S.sig then S.sig, S.big = sg, true end
    if S.big or S.force or t - (S.at or 0) >= 10 then S.at = t; update(t) end
  end
  if isekur.window() then show_window() end
  if isekur.panel then publish_panel(t) end
end)
