-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- radio.lua: /radio, 24/7 radio stations (YouTube lives and plain internet radio) in the webchat, on your phone, or on this machine.
-- The webchat plays the stream in its page (audio only, it keeps going with the screen locked); the terminal plays it with
-- mpv, ffplay or vlc. YouTube lives need yt-dlp and ffmpeg on the machine iSekur runs on; plain streams need only ffmpeg.
-- The station list comes from the plugin's repository (radio/stations.tsv, kept free of dead streams) and is fetched again every
-- `refresh` hours; the list below is what it starts with and falls back to.
if not isekur.radio or not isekur.window then
  print("the radio needs a newer iSekur (API 12)")
  return
end

isekur.setting("output", "auto", "g", "where it plays: auto (the webchat if one is open, else this machine), web, host (this machine's speakers) or both",
               {"auto", "web", "host", "both"})
isekur.setting("source", "host", "g", "host: this machine fetches the stream and relays it to every device (YouTube needs this); direct: the webchat's own device connects to plain https stations, so this machine carries no audio",
               {"host", "direct"})
isekur.setting("stations", "https://raw.githubusercontent.com/gcanosa/isekur-plugins/main/radio/stations.tsv", "g",
               "where the station list is fetched from (an https address of a stations.tsv; empty: only the built-in list)")
isekur.setting("refresh", 24, "g", "hours between station list updates (0: never)")

local function youtube(url) return url:match("^https?://[^/]*youtu") ~= nil end

-- name, address. A YouTube channel's /live is always its current live (a video's own address changes when it restarts)
local BUILTIN = {
  {"Claude FM", "https://www.youtube.com/@claude/live"},
  {"State FM: ambient electronica (State Azure)", "https://www.youtube.com/@stateazure/live"},
  {"Pink Floyd style: Inner World", "https://www.youtube.com/@PeterChers_Josephine/live"},
  {"Pink Floyd style: Solace Sounds", "https://www.youtube.com/@SolaceSoundsStudioLab/live"},
  {"Pink Floyd style: Echoes of Silence", "https://www.youtube.com/@TheLostRockChronicles/live"},
  {"Floyd Runner Radio", "https://www.youtube.com/@LUX-AmbientMusic/live"},
  {"SomaFM Underground 80s: synthpop and new wave", "https://ice4.somafm.com/u80s-128-aac"},
  {"80s Midnight FM", "https://www.youtube.com/@80sMidnightFM/live"},
  {"70s 80s Hits Radio", "https://www.youtube.com/@bestofnostalgia/live"},
  {"Radio 70s 80s Mix", "https://www.youtube.com/@liveradiomix/live"},
  {"RetroPulse FM: 80s synthwave", "https://www.youtube.com/@RetroPulseFM/live"},
  {"New Retro FM: synthwave", "https://www.youtube.com/@NewRetroNet/live"},
  {"Devs FM: Terminal 1987", "https://www.youtube.com/@devsfm/live"},
  {"SomaFM Groove Salad", "https://ice4.somafm.com/groovesalad-128-aac"},
  {"SomaFM Space Station", "https://ice4.somafm.com/spacestation-128-aac"},
  {"SomaFM DEF CON Radio", "https://ice4.somafm.com/defcon-128-aac"},
  {"Radio Paradise", "https://stream.radioparadise.com/mp3-192"},
  {"Radio Paradise: rock mix", "https://stream.radioparadise.com/rock-192"},
}

-- the repository's list: "name<TAB>address" per line, # for comments. The last good one is kept in the store
local function parse(text)
  local out = {}
  for line in text:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and #out < 300 then
      local name, url = line:match("^(.-)\t+(https?://%S+)")
      name = name and name:match("^%s*(.-)%s*$")
      if name and name ~= "" then out[#out + 1] = {name, url} end
    end
  end
  return out
end
local remote = parse(isekur.store_get("list") or "")
local MIN_LIST = 3  -- a list with fewer than this isn't one (an error page, an empty file): it's not taken

-- what a new list changed against the old one, in a few words: "2 new, 1 removed, 1 changed" ("" when nothing did). Matched by address;
-- a station that kept its name under a new address, or its address under a new name, is "changed", not new and removed
local function summary(old, new)
  local oldu, newu, oldn, newn = {}, {}, {}, {}
  for _, s in ipairs(old) do oldu[s[2]], oldn[s[1]] = s[1], s[2] end
  for _, s in ipairs(new) do newu[s[2]], newn[s[1]] = s[1], s[2] end
  local added, removed, changed = 0, 0, 0
  for _, s in ipairs(new) do
    if not oldu[s[2]] then
      if oldn[s[1]] then changed = changed + 1 else added = added + 1 end  -- same name, another address: the old one isn't counted as removed below
    elseif oldu[s[2]] ~= s[1] then changed = changed + 1 end
  end
  for _, s in ipairs(old) do
    if not newu[s[2]] and not newn[s[1]] then removed = removed + 1 end
  end
  local parts = {}
  if added > 0 then parts[#parts + 1] = added .. " new" end
  if removed > 0 then parts[#parts + 1] = removed .. " removed" end
  if changed > 0 then parts[#parts + 1] = changed .. " changed" end
  return table.concat(parts, ", ")
end

-- your own, from /radio add: the store holds one "name<TAB>address" per line
local function custom()
  local out = {}
  for line in (isekur.store_get("custom") or ""):gmatch("[^\n]+") do
    local name, url = line:match("^(.-)\t(.+)$")
    if name then out[#out + 1] = {name, url} end
  end
  return out
end
local function stations()
  local all = {}
  for _, s in ipairs(#remote >= MIN_LIST and remote or BUILTIN) do all[#all + 1] = s end
  for _, s in ipairs(custom()) do all[#all + 1] = s end
  return all
end

local cur = 0       -- the row the window's cursor is on
local out_tab = {}  -- the tab the last command was typed in: where its answers go

local function tell(text, note)
  local srv, target = out_tab[1], out_tab[2]
  if srv == nil and target == nil then srv, target = isekur.active() end
  isekur.print(srv, target, text, note)
end

local function ago(t)
  local s = isekur.time() - t
  if s < 90 then return "just now" end
  if s < 5400 then return math.floor(s / 60 + .5) .. " min ago" end
  if s < 129600 then return math.floor(s / 3600 + .5) .. " h ago" end
  return math.floor(s / 86400 + .5) .. " days ago"
end
local function list_note()  -- where the list is from, for the window and /radio list
  local at = tonumber(isekur.store_get("list_at"))
  if #remote >= MIN_LIST and at then return "list updated " .. ago(at) end
  return "built-in list"
end

-- the volume, 0-150 (100: as the stream comes), kept between runs
local function vol()
  local v = tonumber(isekur.store_get("volume"))
  return v and math.max(0, math.min(150, math.floor(v))) or 100
end
local function set_vol(v)
  v = math.max(0, math.min(150, math.floor(v)))
  isekur.store_set("volume", tostring(v))
  isekur.radio_volume(v)
  return v
end

-- your favorite (the store keeps its name and address, the address first: a renamed station is still it): /radio play with no name starts it
local function fav_index()
  local fn, fu = isekur.store_get("fav"), isekur.store_get("fav_url")
  if not fn and not fu then return 0 end
  local all, byname = stations(), 0
  for i, s in ipairs(all) do
    if fu and s[2] == fu then return i end
    if byname == 0 and s[1] == fn then byname = i end
  end
  return byname
end
local function set_fav(s)
  if s then isekur.store_set("fav", s[1]); isekur.store_set("fav_url", s[2])
  else isekur.store_set("fav", nil); isekur.store_set("fav_url", nil) end
end

local function playing_index()
  local st = isekur.radio()
  if st.state == "off" then return 0 end
  for i, s in ipairs(stations()) do if s[1] == st.name then return i end end
  return 0
end

local function where(st)
  if st.host and st.web then return "this machine and the webchat" end
  return st.host and "this machine's speakers" or "the webchat"
end

local function refresh(force)
  if not force and not isekur.window() then return end
  local st, list = isekur.radio(), {}
  local fav, v = fav_index(), vol()
  for i, s in ipairs(stations()) do list[i] = s[1] end
  if cur > #list then cur = #list end
  local l1, l2
  -- the first line's symbol says at a glance what it's doing: ■ off air, ◌ tuning, ♪ playing
  if st.state == "off" then
    l1 = "\xe2\x96\xa0 Off air"
    l2 = st.err ~= "" and st.err or (#list .. " stations, " .. list_note())
  elseif st.state == "resolving" then
    l1 = "\xe2\x97\x8c Tuning...  " .. st.name
    l2 = "finding the stream"
  else
    l1 = "\xe2\x99\xaa " .. st.name
    l2 = "playing on " .. where(st) .. (st.direct and ", connected directly" or "") .. (st.muted and "  \xc2\xb7  muted" or "")
  end
  isekur.window{title = "Radio", display = {l1, l2}, items = list, sel = cur, mark = playing_index(), star = fav, buttons = {"Play", "Random", "Stop", "Mute", "Fav"},
                 icons = {"\xe2\x96\xb6", "\xe2\x87\x84", "\xe2\x96\xa0", st.muted and "\xe2\x97\x80\xc3\x97" or "\xe2\x97\x80)",
                          "\xe2\x98\x85"},  -- Fav toggles the row under the cursor: the star in the list shows which one is it
                 slider = {value = v, max = 150, step = 5, icon = "vol"},
                 reels = st.state == "playing"}
end

local function stop()
  isekur.radio(false)
  refresh()
end

local function mute()
  if isekur.radio().state == "off" then return "Nothing is playing" end
  isekur.radio_mute(not isekur.radio().muted)
  refresh()
end

local function play(n)
  local s = stations()[n]
  if not s then return "No station " .. tostring(n) .. ": /radio list" end
  local o, st = isekur.opt("output"), isekur.radio()
  local host = o == "host" or o == "both" or (o == "auto" and not st.web)
  -- direct: the browser connects to a plain https station itself; YouTube, http ones and the terminal's speakers go through this machine
  local direct = isekur.opt("source") == "direct" and st.web and not host and s[2]:match("^https://") ~= nil and not youtube(s[2])
  if isekur.opt("source") == "direct" and not direct then tell(s[1] .. " goes through this machine (" .. (youtube(s[2]) and "YouTube can't be played straight from a browser" or not st.web and "no webchat is open" or "it isn't a plain https stream") .. ")", true) end
  local ok, why = isekur.radio(s[2], {name = s[1], host = host, direct = direct, volume = vol()})
  cur = n
  if not ok then
    refresh()
    return "radio: " .. why
  end
  if o == "web" and not st.web then tell("No webchat is open: open it to hear " .. s[1], true) end
  refresh()
end

local function random()
  local all, last = stations(), playing_index()
  if #all == 0 then return end
  local n = math.random(#all)
  if n == last and #all > 1 then n = n % #all + 1 end
  return play(n)
end

local function favorite(n)  -- the station's number: it becomes the favorite, or stops being it when it already is
  local s = stations()[n]
  if not s then return "Pick a station first: /radio list" end
  if fav_index() == n then
    set_fav(nil)
    tell(s[1] .. " is no longer your favorite", true)
  else
    set_fav(s)
    tell(s[1] .. " is your favorite: /radio play starts it", true)
  end
  refresh()
end

-- a station by its number or a part of its name (any case)
local function find(arg)
  local all = stations()
  local n = tonumber(arg)
  if n and all[n] then return n end
  arg = arg:lower()
  for i, s in ipairs(all) do if s[1]:lower():find(arg, 1, true) then return i end end
end

-- the station list: fetched from `stations` when it's older than `refresh` hours (and again after 10 minutes if that failed),
-- or at once for /radio refresh. A reply that isn't a list is ignored: the last good one stays
local fetching = false
local function fetch(say)
  local url = isekur.opt("stations")
  if fetching then return say and "Already fetching it" or nil end
  if url == "" then return say and "No list address: /plugin set radio stations <https address>" or nil end
  if not url:match("^https://") then return say and "The list address must be https" or nil end
  isekur.store_set("list_try", tostring(isekur.time()))
  fetching = true
  local ok, why = isekur.http(url, function(r)
    fetching = false
    local list = r.status == 200 and #r.body <= 65536 and parse(r.body) or {}
    if #list < MIN_LIST then
      if say then tell("Station list: " .. (r.status ~= 200 and (r.error or ("HTTP " .. r.status)) or "that isn't a station list") .. ", keeping the one you have", false) end
      return
    end
    local had_fav = fav_index() > 0
    local what = summary(#remote >= MIN_LIST and remote or BUILTIN, list)
    isekur.store_set("list", r.body)
    isekur.store_set("list_at", tostring(isekur.time()))
    isekur.store_set("list_diff", what ~= "" and what or nil)
    remote = list
    -- a few words, never the list: typed by you (/radio refresh) it answers in your tab; on its own it speaks up in the console, and only when something changed
    local out = say and tell or function(text, note) isekur.print(nil, nil, text, note) end
    if what ~= "" then out("Station list updated: " .. #list .. " stations (" .. what .. ")", true)
    elseif say then out("Station list is up to date: " .. #list .. " stations", true) end
    if had_fav and fav_index() == 0 then out("Your favorite is no longer in the list: /radio fav <station> picks another", true) end
    refresh()
  end)
  if not ok then fetching = false; return say and ("Station list: " .. tostring(why)) or nil end
end
local function due()
  local hours = tonumber(isekur.opt("refresh")) or 24
  if hours <= 0 then return false end
  local now = isekur.time()
  return now - (tonumber(isekur.store_get("list_at")) or 0) >= hours * 3600 and now - (tonumber(isekur.store_get("list_try")) or 0) >= 600
end

local USAGE = "[play [station]|stop|mute|vol [0-150|+n|-n]|fav [station|off]|random|list [text]|refresh|add <address> [name]|del <station>]"
isekur.command("radio", USAGE, function(args, srv, target)
  out_tab = {srv, target}
  local sub, rest = args:match("^(%S*)%s*(.-)%s*$")
  sub = sub:lower()
  if sub == "" then
    cur = cur > 0 and cur or playing_index()
    if cur == 0 then cur = 1 end
    refresh(true)  -- opens it
  elseif sub == "stop" then
    stop()
  elseif sub == "mute" then
    return mute()
  elseif sub == "vol" or sub == "volume" then
    if rest == "" then
      tell("Volume " .. vol() .. "% (/radio vol 0-150, or +10 / -10; 100 is the stream as it comes)", true)
    else
      local rel, n = rest:match("^([+-]?)(%d+)$")
      if not n then return "Usage: /radio vol [0-150|+n|-n]" end
      local v = rel == "+" and vol() + tonumber(n) or rel == "-" and vol() - tonumber(n) or tonumber(n)
      tell("Volume " .. set_vol(v) .. "%", true)
      refresh()
    end
  elseif sub == "fav" then
    if rest == "" then
      local n = fav_index()
      tell(n > 0 and "Your favorite: " .. stations()[n][1] .. " (/radio play starts it, /radio fav off clears it)" or "No favorite yet: /radio fav <station>, or Fav in the window. /radio play picks a random one", true)
    elseif rest:lower() == "off" or rest:lower() == "none" then
      set_fav(nil)
      tell("No favorite now: /radio play picks a random one", true)
      refresh()
    else
      local n = find(rest)
      if not n then return "No station like \"" .. rest .. "\": /radio list" end
      set_fav(stations()[n])
      tell(stations()[n][1] .. " is your favorite: /radio play starts it", true)
      refresh()
    end
  elseif sub == "random" then
    return random()
  elseif sub == "play" then
    if rest == "" then
      local n = fav_index()
      if n > 0 then return play(n) end
      return random()
    end
    local n = find(rest)
    if not n then return "No station like \"" .. rest .. "\": /radio list" end
    return play(n)
  elseif sub == "refresh" then
    local err = fetch(true)
    if err then return err end
    tell("Fetching the station list...", true)
  elseif sub == "list" then
    -- never the whole list in the console: a summary, or the stations that match a text (the window has them all)
    local last = isekur.store_get("list_diff")
    local head = #stations() .. " stations, " .. list_note() .. (last and #remote >= MIN_LIST and " (" .. last .. ")" or "")
    if rest == "" then
      tell(head .. ": /radio opens the window, /radio list <text> finds one, /radio play <name or number>", true)
    else
      local now, fav, q, shown, total = playing_index(), fav_index(), rest:lower(), 0, 0
      for i, s in ipairs(stations()) do
        if s[1]:lower():find(q, 1, true) then
          total = total + 1
          if shown < 10 then
            shown = shown + 1
            tell(string.format("%s%2d  %s%s", i == now and "\xe2\x96\xb6 " or "  ", i, i == fav and "\xe2\x98\x85 " or "", s[1]), false)
          end
        end
      end
      if total == 0 then tell("No station like \"" .. rest .. "\" in " .. head, true)
      elseif total > shown then tell("... and " .. (total - shown) .. " more: a longer text narrows it", true) end
    end
  elseif sub == "add" then
    local url, name = rest:match("^(%S+)%s*(.-)$")
    if not url or not url:match("^https?://") then return "Usage: /radio add <https address> [name]" end
    name = name ~= "" and name or url:match("^https?://([^/]+)")
    isekur.store_set("custom", (isekur.store_get("custom") or "") .. name:gsub("[\t\n]", " ") .. "\t" .. url .. "\n")
    tell("Added: " .. name .. " (number " .. #stations() .. ")", true)
    refresh()
  elseif sub == "del" then
    local n = find(rest)
    local own = #stations() - #custom()
    if not n or n <= own then return "Only the stations you added can go: /radio list" end
    local kept, i = {}, 0
    for _, s in ipairs(custom()) do
      i = i + 1
      if i + own ~= n then kept[#kept + 1] = s[1] .. "\t" .. s[2] .. "\n" end
    end
    isekur.store_set("custom", table.concat(kept))
    cur = 0
    tell("Removed.", true)
    refresh()
  else
    return "Usage: /radio " .. USAGE
  end
end)

isekur.on("window", function(e)
  out_tab = {}
  if e.action == "close" then return end
  if e.action == "slider" then
    set_vol(e.value)
    refresh()
    return
  end
  if e.index and e.index > 0 then cur = e.index end
  local err
  if e.action == "pick" or e.button == "Play" then err = play(cur)
  elseif e.button == "Random" then err = random()
  elseif e.button == "Stop" then stop()
  elseif e.button == "Mute" then err = mute()
  elseif e.button == "Fav" then err = favorite(cur) end
  if err then tell(err, false) end
end)

-- every second: the station list when it's due, and the window follows what the radio does (tuning, playing, why it stopped)
local sig = ""
isekur.on("tick", function()
  if not fetching and due() then fetch(false) end
  if not isekur.window() then return end
  local st = isekur.radio()
  local now = st.state .. st.name .. st.err .. tostring(st.web) .. tostring(st.muted)
  if now ~= sig then sig = now; refresh() end
end)
