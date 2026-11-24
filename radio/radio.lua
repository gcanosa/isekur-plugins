-- version: 1.2
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- radio.lua: /radio, internet radio in the webchat, on your phone, or on this machine: a hand-picked list (Recommended), the Radio Browser
-- directory of ~50,000 stations (Browse and Search), and your own (Mine).
-- The webchat plays the stream in its page (audio only, it keeps going with the screen locked); the terminal plays it with
-- mpv, ffplay or vlc. YouTube lives need yt-dlp and ffmpeg on the machine iSekur runs on; plain streams need only ffmpeg.
-- The recommended list comes from the plugin's repository (radio/stations.tsv, kept free of dead streams) and is fetched again every
-- `refresh` hours; the list below is what it starts with and falls back to. The directory is https://www.radio-browser.info (a community
-- project): Browse and Search ask it, and playing one of its stations tells it so (that is what makes the votes and trends); set
-- `directory` to off to leave it out.
if not isekur.radio or not isekur.window or not isekur.json_decode or (isekur.api or 0) < 17 then
  print("the radio needs a newer iSekur (API 17)")
  return
end

isekur.setting("output", "auto", "g", "where it plays: auto (the webchat if one is open, else this machine), web, host (this machine's speakers) or both",
               {"auto", "web", "host", "both"})
isekur.setting("source", "host", "g", "host: this machine fetches the stream and relays it to every device (YouTube needs this); direct: the webchat's own device connects to plain https stations, so this machine carries no audio",
               {"host", "direct"})
isekur.setting("stations", "https://raw.githubusercontent.com/gcanosa/isekur-plugins/main/radio/stations.tsv", "g",
               "where the recommended list is fetched from (an https address of a stations.tsv; off: only the built-in list)")
isekur.setting("refresh", 24, "g", "hours between recommended list updates (0: never)")
isekur.setting("directory", "https://de1.api.radio-browser.info", "g",
               "the station directory Browse and Search use (radio-browser.info: searches and the stations you play are known to it; off: no directory)")

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

-- a station is {name, url, id?, sub?}: id is the directory's (it finds the stream again when the address changes), sub the second line of its row
local function builtin()
  local out = {}
  for i, s in ipairs(BUILTIN) do out[i] = {name = s[1], url = s[2]} end
  return out
end

-- the repository's list: "name<TAB>address" per line, # for comments. The last good one is kept in the store
local function parse(text)
  local out = {}
  for line in text:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and #out < 300 then
      local name, url = line:match("^(.-)\t+(https?://%S+)")
      name = name and name:match("^%s*(.-)%s*$")
      if name and name ~= "" then out[#out + 1] = {name = name, url = url} end
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
  for _, s in ipairs(old) do oldu[s.url], oldn[s.name] = s.name, s.url end
  for _, s in ipairs(new) do newu[s.url], newn[s.name] = s.name, s.url end
  local added, removed, changed = 0, 0, 0
  for _, s in ipairs(new) do
    if not oldu[s.url] then
      if oldn[s.name] then changed = changed + 1 else added = added + 1 end  -- same name, another address: the old one isn't counted as removed below
    elseif oldu[s.url] ~= s.name then changed = changed + 1 end
  end
  for _, s in ipairs(old) do
    if not newu[s.url] and not newn[s.name] then removed = removed + 1 end
  end
  local parts = {}
  if added > 0 then parts[#parts + 1] = added .. " new" end
  if removed > 0 then parts[#parts + 1] = removed .. " removed" end
  if changed > 0 then parts[#parts + 1] = changed .. " changed" end
  return table.concat(parts, ", ")
end

local function recs() return #remote >= MIN_LIST and remote or builtin() end

-- Mine: the stations you added (/radio add) or kept from the directory (Add): the store holds one "name<TAB>address<TAB>id<TAB>sub" per line
local MAX_MINE = 300
local function mine()
  local out = {}
  for line in (isekur.store_get("custom") or ""):gmatch("[^\n]+") do
    local name, url, id, sub = line:match("^([^\t]*)\t([^\t]*)\t?([^\t]*)\t?(.*)$")
    if name and url ~= "" then out[#out + 1] = {name = name, url = url, id = id ~= "" and id or nil, sub = sub ~= "" and sub or url:match("^https?://([^/]+)")} end  -- no second line of its own: where it is from
  end
  return out
end
local function save_mine(list)
  local lines = {}
  for i, s in ipairs(list) do
    lines[i] = (s.name:gsub("[\t\n]", " ")) .. "\t" .. s.url .. "\t" .. (s.id or "") .. "\t" .. ((s.sub or ""):gsub("[\t\n]", " ")) .. "\n"
  end
  isekur.store_set("custom", #lines > 0 and table.concat(lines) or nil)
end
local function stations()  -- /radio play, list, fav and del name stations of both lists, numbered Recommended first
  local all = {}
  for _, s in ipairs(recs()) do all[#all + 1] = s end
  for _, s in ipairs(mine()) do all[#all + 1] = s end
  return all
end
local function same(a, b) return a and b and ((a.id and a.id == b.id) or a.url == b.url) end

local TABS = {"Recommended", "Browse", "Search", "Mine"}
local T_REC, T_BROWSE, T_SEARCH, T_MINE = 1, 2, 3, 4
local PAGE, MAXROWS = 50, 250
local tab = T_REC
local cur = 0          -- the row the window's cursor is on
local out_tab = {}     -- the tab the last command was typed in: where its answers go
local now_st = nil     -- the station last started (what /radio save keeps)
local pending = nil    -- a directory station whose address is being asked for
local chain = nil      -- while a station started from a list is tuning: {list, i, tries, noyt}: if it doesn't work the next one is tried

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
local function list_note()  -- where the recommended list is from, for the window and /radio list
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

-- your favorite (the store keeps its name, address and directory id, the id and address first: a renamed station is still it): /radio play with no name starts it
local function fav_idx(list)
  local fn, fu, fi = isekur.store_get("fav"), isekur.store_get("fav_url"), isekur.store_get("fav_id")
  if not fn and not fu then return 0 end
  local byname = 0
  for i, s in ipairs(list) do
    if (fi and s.id == fi) or (fu and s.url == fu) then return i end
    if byname == 0 and s.name == fn then byname = i end
  end
  return byname
end
local function fav_index() return fav_idx(stations()) end
local function is_fav(s)  -- by id or address only: a station with the favorite's name isn't it
  local fu, fi = isekur.store_get("fav_url"), isekur.store_get("fav_id")
  return (fi ~= nil and s.id == fi) or (fu ~= nil and s.url == fu)
end
local function set_fav(s)
  if s then isekur.store_set("fav", s.name); isekur.store_set("fav_url", s.url); isekur.store_set("fav_id", s.id)
  else isekur.store_set("fav", nil); isekur.store_set("fav_url", nil); isekur.store_set("fav_id", nil) end
end

local function where(st)
  if st.host and st.web then return "this machine and the webchat" end
  return st.host and "this machine's speakers" or "the webchat"
end

-- ---- the directory (radio-browser.info) ---------------------------------------------------------------------------------------
local HDR = {headers = {["User-Agent"] = "iSekur-radio/1.1", Accept = "application/json"}}
local function is_off(v) v = v:lower(); return v == "" or v == "off" or v == "none" or v == "no" end  -- a setting can't be empty (that is its default): off is the switch
local function dir_base()
  local b = isekur.opt("directory"):gsub("/+$", "")
  return not is_off(b) and b or nil
end
-- explicit ASCII classes below: %c, %s and %w follow the C library, which on some systems calls bytes of UTF-8 text (0x80-0xA0) controls or spaces
local function enc(s) return (tostring(s):gsub("[^A-Za-z0-9%-%._~]", function(c) return string.format("%%%02X", c:byte()) end)) end
local function clean(s) return (tostring(s == nil and "" or s):gsub("[\0-\31\127]+", " "):gsub(" +", " "):match("^ *(.-) *$")) end

-- fn(data) or fn(nil, why)
local function api(path, fn)
  local base = dir_base()
  if not base then return fn(nil, "the directory is off: /plugin set radio directory (alone: back to the default)") end
  local ok, why = isekur.http(base .. "/json/" .. path, function(r)
    if r.status ~= 200 then return fn(nil, r.error or ("HTTP " .. r.status)) end
    local d, e = isekur.json_decode(r.body)
    if d == nil then return fn(nil, "an answer that isn't a list (" .. tostring(e) .. ")") end
    fn(d)
  end, nil, HDR)
  if not ok then fn(nil, why) end
end

local function kilo(n)
  n = tonumber(n) or 0
  if n >= 10000 then return math.floor(n / 1000) .. "k" end
  if n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n))
end

-- a station of the directory as a row: its name, and a second line with where, what, how and how loved ("US · jazz, smooth jazz · MP3 192k · ♥ 92k")
local function from_api(r)
  if type(r) ~= "table" then return nil end
  local url = type(r.url_resolved) == "string" and r.url_resolved ~= "" and r.url_resolved or r.url
  if type(url) ~= "string" or not url:match("^https?://") or url:find("[ \t\r\n]") then return nil end
  local name = clean(r.name)
  if name == "" then name = "(no name)" end
  local bits = {}
  local cc = clean(r.countrycode)
  if cc ~= "" then bits[#bits + 1] = cc elseif clean(r.country) ~= "" then bits[#bits + 1] = clean(r.country) end
  local tags = {}
  for raw in tostring(r.tags or ""):gmatch("[^,]+") do
    local t = clean(raw)
    if t ~= "" and #t <= 20 and #tags < 3 then tags[#tags + 1] = t end
  end
  if #tags > 0 then bits[#bits + 1] = table.concat(tags, ", ") end
  local codec, br = clean(r.codec), tonumber(r.bitrate) or 0
  if codec ~= "" and codec ~= "UNKNOWN" then bits[#bits + 1] = codec .. (br > 0 and (" " .. math.floor(br) .. "k") or "")
  elseif br > 0 then bits[#bits + 1] = math.floor(br) .. "k" end
  if (tonumber(r.votes) or 0) > 0 then bits[#bits + 1] = "\xe2\x99\xa5 " .. kilo(r.votes) end
  return {name = name, url = url, id = type(r.stationuuid) == "string" and r.stationuuid or nil, sub = table.concat(bits, " \xc2\xb7 ")}
end

-- ---- views: what Browse and Search show, a list that is fetched --------------------------------------------------------------
-- a view: {crumb, kind = root|list|stations|countries|tags|langs, rows, busy, err, loaded, more}. A row is a station, or a node ({go = function} opens
-- something or does something) or a note (nothing happens). Each fetch writes into its own view, so an answer that comes after you went elsewhere is harmless
local refresh
local uid = 0
local function newview(t)
  uid = uid + 1
  t.uid, t.rows = uid, t.rows or {}
  return t
end

local CATS = {
  countries = "countries?order=stationcount&reverse=true&hidebroken=true",
  tags = "tags?order=stationcount&reverse=true&hidebroken=true&limit=300",
  langs = "languages?order=stationcount&reverse=true&hidebroken=true&limit=150",
}
local function load(v)  -- the first page of a list of stations, the next one, or the whole list of a category
  if v.busy then return end
  v.busy, v.err = true, nil
  local path = v.kind == "stations" and ("stations/search?hidebroken=true&limit=" .. PAGE .. "&offset=" .. v.off .. "&" .. v.q) or CATS[v.kind]
  api(path, function(d, why)
    v.busy = false
    if not d then
      v.err = why
    elseif v.kind == "stations" then
      for _, r in ipairs(d) do
        local s = from_api(r)
        if s and #v.rows < MAXROWS then v.rows[#v.rows + 1] = s end
      end
      v.off = v.off + PAGE
      v.more = #d >= PAGE and #v.rows < MAXROWS
      v.capped = #d >= PAGE and #v.rows >= MAXROWS
      v.loaded = true
    else
      v.rows = v.first and {v.first} or {}
      for _, r in ipairs(d) do
        local n = tonumber(r.stationcount) or 0
        local name = clean(r.name):gsub("^The ", "")
        local key, label = clean(r.name), name
        if v.kind == "countries" then key = clean(r.iso_3166_1)
        elseif v.kind == "langs" then label = name:sub(1, 1):upper() .. name:sub(2) end
        local keep = n >= (v.kind == "tags" and 10 or 1) and label ~= "" and key ~= "" and not (v.kind == "tags" and (#label < 2 or label:match("^[%d%p%s]+$")))
        if keep and #v.rows < 280 then
          v.rows[#v.rows + 1] = {name = label, sub = kilo(n) .. (n == 1 and " station" or " stations"), go = function() v.onpick(label, key) end}
        end
      end
      v.loaded = true
    end
    refresh()
  end)
end
local function stations_view(crumb, q) return newview{crumb = crumb, kind = "stations", q = q, off = 0} end
local function cat_view(crumb, kind, onpick, first) return newview{crumb = crumb, kind = kind, onpick = onpick, first = first} end

-- the rows of a view as shown: loading, a failure (Enter tries again), More..., nothing found
local function shown(v)
  local out = {}
  for _, e in ipairs(v.rows) do out[#out + 1] = e end
  if v.err then out[#out + 1] = {name = "Couldn't load: " .. v.err, sub = "Enter tries again", go = function() v.err = nil; load(v); refresh() end}
  elseif v.busy then out[#out + 1] = {name = "Loading...", sub = "asking the directory", note = true}
  elseif v.more then out[#out + 1] = {name = "More...", sub = "the next " .. PAGE, go = function() load(v); refresh() end}
  elseif v.capped then out[#out + 1] = {name = "That's the first " .. #v.rows, sub = "narrow it down: Refine in Search, or a smaller category", note = true}
  elseif v.loaded and #v.rows == 0 then out[#out + 1] = {name = "Nothing here", sub = "no station matches", note = true} end
  return out
end

-- Browse: a root and the places you opened from it; Back (or Backspace) goes up
local B = {stack = {}}
local function bpush(v)
  if B.v then B.v.at = cur; B.stack[#B.stack + 1] = B.v end
  B.v, cur = v, 1
  if not v.loaded and v.kind ~= "root" then load(v) end
  refresh()
end
local function bhome()
  local v = newview{crumb = "Browse", kind = "root"}
  local function places(crumb, q) return function() bpush(stations_view(crumb, q)) end end
  v.rows = {
    {name = "Top voted", sub = "the stations people like most", go = places("Top voted", "order=votes&reverse=true")},
    {name = "Trending now", sub = "what people are tuning in to", go = places("Trending now", "order=clicktrend&reverse=true")},
    {name = "By country", sub = "pick a country", go = function()
      bpush(cat_view("By country", "countries", function(name, code) bpush(stations_view(name, "countrycode=" .. enc(code) .. "&order=votes&reverse=true")) end)) end},
    {name = "By genre", sub = "jazz, ambient, metal, news...", go = function()
      bpush(cat_view("By genre", "tags", function(name) bpush(stations_view(name, "tag=" .. enc(name) .. "&tagExact=true&order=votes&reverse=true")) end)) end},
    {name = "By language", sub = "pick a language", go = function()
      bpush(cat_view("By language", "langs", function(name, key) bpush(stations_view(name, "language=" .. enc(key) .. "&languageExact=true&order=votes&reverse=true")) end)) end},
  }
  v.loaded = true
  B.v, B.stack = v, {}
end
bhome()

-- Search: the text of the field plus what Refine narrows it to (a country, a genre, a language, a quality)
local S = {q = "", pstack = {}}
local function filters_on() return S.country or S.tag or S.lang or S.minbr end
local function search_run()
  S.v = nil
  if S.q == "" and not filters_on() then return end
  local p = {"order=votes", "reverse=true"}
  if S.q ~= "" then p[#p + 1] = "name=" .. enc(S.q) end
  if S.country then p[#p + 1] = S.country.code and ("countrycode=" .. enc(S.country.code)) or ("country=" .. enc(S.country.name)) end
  if S.tag then p[#p + 1] = "tag=" .. enc(S.tag) .. "&tagExact=true" end
  if S.lang then p[#p + 1] = "language=" .. enc(S.lang) .. "&languageExact=true" end
  if S.minbr then p[#p + 1] = "bitrateMin=" .. S.minbr end
  S.v = stations_view("Search", table.concat(p, "&"))
  load(S.v)
end
local function search_done()  -- a filter was picked: back to the results, for it
  S.pick, S.pstack, cur = nil, {}, 1
  search_run()
  refresh()
end
local function ppush(v)
  if S.pick then S.pick.at = cur; S.pstack[#S.pstack + 1] = S.pick end
  S.pick, cur = v, 1
  if not v.loaded and v.kind ~= "root" and v.kind ~= "list" then load(v) end
  refresh()
end
local function refine_home()
  local v = newview{crumb = "Refine", kind = "root"}
  local function any(label, set) return {name = label, sub = "no limit", go = function() set(); search_done() end} end
  local QUAL = {{"At least 64 kbps", 64}, {"At least 128 kbps", 128}, {"At least 192 kbps", 192}}
  v.rows = {
    {name = "Country: " .. (S.country and S.country.name or "any"), sub = "only stations from one country", go = function()
      ppush(cat_view("Country", "countries", function(name, code) S.country = {name = name, code = code}; search_done() end, any("Any country", function() S.country = nil end))) end},
    {name = "Genre: " .. (S.tag or "any"), sub = "jazz, ambient, metal...", go = function()
      ppush(cat_view("Genre", "tags", function(name) S.tag = name; search_done() end, any("Any genre", function() S.tag = nil end))) end},
    {name = "Language: " .. (S.lang or "any"), sub = "the language they speak", go = function()
      ppush(cat_view("Language", "langs", function(name, key) S.lang = key; search_done() end, any("Any language", function() S.lang = nil end))) end},
    {name = "Quality: " .. (S.minbr and ("at least " .. S.minbr .. " kbps") or "any"), sub = "a higher bitrate sounds better and uses more data", go = function()
      local q = newview{crumb = "Quality", kind = "list", loaded = true}
      q.rows = {any("Any quality", function() S.minbr = nil end)}
      for _, o in ipairs(QUAL) do q.rows[#q.rows + 1] = {name = o[1], go = function() S.minbr = o[2]; search_done() end} end
      ppush(q) end},
    {name = "Clear everything", sub = "the words and every limit", go = function() S.q, S.country, S.tag, S.lang, S.minbr = "", nil, nil, nil, nil; search_done() end},
  }
  v.loaded = true
  ppush(v)
end
local function search_for(text)
  S.q, S.pick, S.pstack, cur = text or "", nil, {}, 1
  search_run()
end

-- the view the window shows now
local function current_view()
  if tab == T_BROWSE then return B.v end
  if tab == T_SEARCH then return S.pick or S.v end
end
local function entries()
  if tab == T_REC then return recs() end
  if tab == T_MINE then
    local list = mine()
    if #list == 0 then return {{name = "Nothing here yet", sub = "Add (+) a station from Browse or Search", note = true}} end
    return list
  end
  if not dir_base() then
    return {{name = "The station directory is off", sub = "/plugin set radio directory   (alone: back to the default)", note = true}}
  end
  local v = current_view()
  if v then return shown(v) end
  if tab == T_SEARCH then
    return {{name = filters_on() and "Nothing yet: press Enter in the field" or "Type a name above and press Enter", sub = "Refine narrows it by country, genre, language or quality", note = true}}
  end
  return {}
end
local function is_station(e) return e and e.url ~= nil and not e.go end

-- ---- playing --------------------------------------------------------------------------------------------------------------------
local playgen = 0
local function playing_index(list)
  local st = isekur.radio()
  if st.state == "off" then return 0 end
  if now_st and st.name == now_st.name then
    for i, s in ipairs(list) do if is_station(s) and same(s, now_st) then return i end end
  end
  for i, s in ipairs(list) do if is_station(s) and s.name == st.name then return i end end
  return 0
end

local function start_radio(s, url)  -- the radio on url: true, or false and why
  local o, st = isekur.opt("output"), isekur.radio()
  local host = o == "host" or o == "both" or (o == "auto" and not st.web)
  -- direct: the browser connects to a plain https station itself; YouTube, http ones and the terminal's speakers go through this machine
  local direct = isekur.opt("source") == "direct" and st.web and not host and url:match("^https://") ~= nil and not youtube(url)
  if isekur.opt("source") == "direct" and not direct then tell(s.name .. " goes through this machine (" .. (youtube(url) and "YouTube can't be played straight from a browser" or not st.web and "no webchat is open" or "it isn't a plain https stream") .. ")", true) end
  local ok, why = isekur.radio(url, {name = s.name, host = host, direct = direct, volume = vol()})
  now_st = s
  if not ok then return false, why end
  if o == "web" and not st.web then tell("No webchat is open: open it to hear " .. s.name, true) end
  return true
end

local begin_play
-- it didn't start (or never gave sound): inside a list the next station is tried, saying why this one wasn't (a few times: a list of dead ones isn't walked to its end)
local function failed(s, why)
  why = why:gsub("^%[[^%]]*%] *", "")  -- ffmpeg's "[tls @ 0x7f...]" tells the reader nothing
  local c = chain
  if not c then tell(s.name .. ": " .. why, false); return end
  if why:find("ffmpeg isn't installed", 1, true) or why:find("no player", 1, true) then chain = nil; tell(why, false); return end  -- every station would say the same
  if why:find("yt-dlp isn't installed", 1, true) then c.noyt = true end
  c.tries = c.tries + 1
  local nxt
  for i = c.i + 1, #c.list do
    local e = c.list[i]
    if is_station(e) and not (c.noyt and youtube(e.url)) then nxt = i; break end
  end
  if not nxt or c.tries > 4 then
    chain = nil
    tell(s.name .. ": " .. why .. (c.tries > 4 and ". Stopped after 4 stations that didn't work" or ". Nothing else in this list to try"), false)
    return
  end
  c.i = nxt
  local shown_now = entries()
  if same(shown_now[nxt], c.list[nxt]) then cur = nxt end  -- the cursor goes along while that list is the one in the window
  tell(s.name .. ": " .. why .. ". Trying " .. c.list[nxt].name, true)
  begin_play(c.list[nxt])
end

-- starts a station; a directory one first asks for its current address (that also counts a listen), the stored one when it can't be had
function begin_play(s)
  local mine_gen = playgen + 1
  playgen = mine_gen
  local function go(url)
    if mine_gen ~= playgen then return end
    pending = nil
    local ok, why = start_radio(s, url)
    if not ok then failed(s, why) end
    refresh()
  end
  local base = s.id and dir_base()
  if not base then pending = nil; return go(s.url) end
  pending = s
  local ok = isekur.http(base .. "/json/url/" .. enc(s.id), function(r)
    local d = r.status == 200 and isekur.json_decode(r.body)
    local url = type(d) == "table" and d.ok and type(d.url) == "string" and d.url:match("^https?://") and not d.url:find("[ \t\r\n]") and d.url or s.url
    go(url)
  end, nil, HDR)
  if not ok then go(s.url) end
  refresh()
end

local function stop()
  chain, pending, playgen = nil, nil, playgen + 1
  isekur.radio(false)
  refresh()
end

local function mute()
  if isekur.radio().state == "off" then return "Nothing is playing" end
  isekur.radio_mute(not isekur.radio().muted)
  refresh()
end

local function play_from(list, i)  -- the user picked list[i]: it plays, and if it doesn't the ones after it are tried
  local s = list[i]
  if not is_station(s) then return end
  cur = i
  chain = {list = list, i = i, tries = 1}
  begin_play(s)
end

local function random_in(list)
  local idx = {}
  for i, s in ipairs(list) do if is_station(s) then idx[#idx + 1] = i end end
  if #idx == 0 then return end
  local last = playing_index(list)
  local n = idx[math.random(#idx)]
  while n == last and #idx > 1 do n = idx[math.random(#idx)] end
  return play_from(list, n)
end

-- Mine and the favorite
local function keep(s)  -- a station of the directory (or any) into Mine: true when it was added, false when it was there, nil when Mine is full
  local list = mine()
  for _, m in ipairs(list) do if same(m, s) then return false end end
  if #list >= MAX_MINE then return nil end
  list[#list + 1] = {name = s.name, url = s.url, id = s.id, sub = s.sub}
  save_mine(list)
  return true
end
local function add_to_mine(s)
  local r = keep(s)
  if r == nil then tell("Mine is full (" .. MAX_MINE .. "): remove one first", true)
  elseif r then tell("Added to Mine: " .. s.name, true)
  else tell(s.name .. " is in Mine already", true) end
  refresh()
end
local function favorite(s)  -- it becomes the favorite, or stops being it when it already is
  if not is_station(s) then return "Pick a station first" end
  if is_fav(s) then
    set_fav(nil)
    tell(s.name .. " is no longer your favorite", true)
  else
    local inrec = false
    for _, r in ipairs(recs()) do if same(r, s) then inrec = true end end
    if not inrec and keep(s) then tell("Added to Mine: " .. s.name, true) end  -- the favorite has to be somewhere you can find it
    set_fav(s)
    tell(s.name .. " is your favorite: /radio play starts it", true)
  end
  refresh()
end
local function del_mine(s)
  local kept = {}
  for _, m in ipairs(mine()) do if not same(m, s) then kept[#kept + 1] = m end end
  save_mine(kept)
  if is_fav(s) then set_fav(nil) end
  cur = math.max(1, math.min(cur, #kept))
  tell("Removed " .. s.name .. " from Mine", true)
  refresh()
end

-- ---- the window --------------------------------------------------------------------------------------------------------------------
local ICON = {Play = "\xe2\x96\xb6", Open = "\xe2\x86\x92", Random = "\xe2\x87\x84", Stop = "\xe2\x96\xa0", Fav = "\xe2\x98\x85", Add = "+", Del = "\xe2\x9c\x95",
              Back = "\xe2\x86\x90", Refine = "\xe2\x89\xa1"}
local function buttons(st)
  local b
  if tab == T_REC then b = {"Play", "Random", "Stop", "Mute", "Fav"}
  elseif tab == T_MINE then b = {"Play", "Random", "Stop", "Mute", "Fav", "Del"}
  elseif not dir_base() then b = {"Stop", "Mute"}
  else
    local v = current_view()
    local stations_here = v ~= nil and v.kind == "stations"
    if stations_here then b = {"Play", "Add", "Fav", "Stop", "Mute"}
    elseif v ~= nil then b = {"Open", "Stop", "Mute"}
    else b = {"Stop", "Mute"} end
    if tab == T_SEARCH and not S.pick then table.insert(b, stations_here and #b + 1 or 1, "Refine") end  -- before there are results it comes first
    if (tab == T_BROWSE and #B.stack > 0) or (tab == T_SEARCH and S.pick) then b[#b + 1] = "Back" end
  end
  local icons = {}
  for i, n in ipairs(b) do icons[i] = n == "Mute" and (st.muted and "\xe2\x97\x80\xc3\x97" or "\xe2\x97\x80)") or ICON[n] or "" end
  return b, icons
end

local function context(ents)
  if tab == T_MINE then return (#mine() > 0 and #mine() or "none") .. " of your own, the star is your favorite" end
  if tab == T_BROWSE then
    local names = {}
    for _, v in ipairs(B.stack) do names[#names + 1] = v.crumb end
    names[#names + 1] = B.v.crumb
    return table.concat(names, " \xe2\x80\xba ")
  end
  if tab == T_SEARCH then
    if S.pick then
      local names = {}
      for _, v in ipairs(S.pstack) do names[#names + 1] = v.crumb end
      names[#names + 1] = S.pick.crumb
      return table.concat(names, " \xe2\x80\xba ")
    end
    local bits = {}
    if S.q ~= "" then bits[#bits + 1] = "\"" .. S.q .. "\"" end
    if S.country then bits[#bits + 1] = S.country.name end
    if S.tag then bits[#bits + 1] = S.tag end
    if S.lang then bits[#bits + 1] = S.lang end
    if S.minbr then bits[#bits + 1] = ">= " .. S.minbr .. " kbps" end
    return #bits > 0 and ("Search: " .. table.concat(bits, " \xc2\xb7 ")) or "Search the whole directory by name"
  end
end

function refresh(force)
  if not force and not isekur.window() then return end
  local st = isekur.radio()
  local ents = entries()
  if cur > #ents then cur = #ents end
  if cur < 1 and #ents > 0 then cur = 1 end
  local items, subs, anysub = {}, {}, false
  for i, e in ipairs(ents) do
    items[i], subs[i] = e.name, e.sub or ""
    if e.sub then anysub = true end
  end
  local l1, l2
  -- the first line's symbol says at a glance what it's doing: ■ off air, ◌ tuning, ♪ playing
  if pending then
    l1, l2 = "\xe2\x97\x8c Tuning...  " .. pending.name, "asking the directory for its address"
  elseif st.state == "off" then
    l1 = "\xe2\x96\xa0 Off air"
    l2 = st.err ~= "" and st.err or (tab == T_REC and (#ents .. " stations, " .. list_note()) or "pick a station and press Play")
  elseif st.state == "resolving" then
    l1 = "\xe2\x97\x8c Tuning...  " .. st.name
    l2 = "finding the stream"
  else
    l1 = "\xe2\x99\xaa " .. st.name
    l2 = "playing on " .. where(st) .. (st.direct and ", connected directly" or "") .. (st.muted and "  \xc2\xb7  muted" or "")
  end
  local b, icons = buttons(st)
  local v = current_view()
  local lid = tab == T_REC and "rec" or tab == T_MINE and "mine" or (v and "v" .. v.uid or "none" .. tab)
  local searching = tab == T_SEARCH and not S.pick and dir_base() ~= nil
  isekur.window{title = "Radio", display = {l1, l2, context(ents)}, items = items, subs = anysub and subs or nil, sel = cur, mark = playing_index(ents), star = fav_idx(ents),
                buttons = b, icons = icons, slider = {value = vol(), max = 150, step = 5, icon = "vol"}, reels = st.state == "playing",
                tabs = TABS, tab = tab, list = lid, search = searching and "Search stations by name" or nil, query = searching and S.q or ""}
end

local function switch(n)
  if n < 1 or n > #TABS then return end
  tab = n
  local ents = entries()
  cur = #ents > 0 and 1 or 0
  if n == T_REC or n == T_MINE then  -- the cursor starts on what plays, else on the favorite
    local p, f = playing_index(ents), fav_idx(ents)
    cur = p > 0 and p or f > 0 and f or cur
  end
  refresh()
end

-- ---- commands -------------------------------------------------------------------------------------------------------------------
-- a station by its number or a part of its name (any case)
local function find(arg)
  local all = stations()
  local n = tonumber(arg)
  if n and all[n] then return n end
  arg = arg:lower()
  for i, s in ipairs(all) do if s.name:lower():find(arg, 1, true) then return i end end
end

-- the recommended list: fetched from `stations` when it's older than `refresh` hours (and again after 10 minutes if that failed),
-- or at once for /radio refresh. A reply that isn't a list is ignored: the last good one stays
local fetching = false
local function fetch(say)
  local url = isekur.opt("stations")
  if fetching then return say and "Already fetching it" or nil end
  if is_off(url) then return say and "The list is off: /plugin set radio stations <https address> (without an address: the default one)" or nil end
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
    local what = summary(recs(), list)
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

local USAGE = "[play [station]|stop|mute|vol [0-150|+n|-n]|fav [station|off]|random|list [text]|find <words> [country:AR tag:jazz lang:spanish min:128]|top|save|refresh|add <address> [name]|del <station>]"
isekur.command("radio", USAGE, function(args, srv, target)
  out_tab = {srv, target}
  local sub, rest = args:match("^(%S*)%s*(.-)%s*$")
  sub = sub:lower()
  if sub == "" then
    if cur == 0 then switch(tab) end  -- the first time: the cursor on what plays, or the favorite
    refresh(true)  -- opens it, where you left it
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
      tell(n > 0 and "Your favorite: " .. stations()[n].name .. " (/radio play starts it, /radio fav off clears it)" or "No favorite yet: /radio fav <station>, or Fav in the window. /radio play picks a random one", true)
    elseif rest:lower() == "off" or rest:lower() == "none" then
      set_fav(nil)
      tell("No favorite now: /radio play picks a random one", true)
      refresh()
    else
      local n = find(rest)
      if not n then return "No station like \"" .. rest .. "\": /radio list" end
      set_fav(stations()[n])
      tell(stations()[n].name .. " is your favorite: /radio play starts it", true)
      refresh()
    end
  elseif sub == "random" then
    return random_in(stations())
  elseif sub == "play" then
    local all = stations()
    if rest == "" then
      local n = fav_index()
      if n > 0 then return play_from(all, n) end
      return random_in(all)
    end
    local n = find(rest)
    if not n then return "No station like \"" .. rest .. "\": /radio list" end
    return play_from(all, n)
  elseif sub == "refresh" then
    local err = fetch(true)
    if err then return err end
    tell("Fetching the station list...", true)
  elseif sub == "list" then
    -- never the whole list in the console: a summary, or the stations that match a text (the window has them all)
    local last = isekur.store_get("list_diff")
    local head = #stations() .. " stations (" .. #mine() .. " yours), " .. list_note() .. (last and #remote >= MIN_LIST and " (" .. last .. ")" or "")
    if rest == "" then
      tell(head .. ": /radio opens the window, /radio list <text> finds one, /radio play <name or number>, /radio find <words> searches the directory", true)
    else
      local all = stations()
      local fav, now, q, shown_n, total = fav_index(), playing_index(all), rest:lower(), 0, 0
      for i, s in ipairs(all) do
        if s.name:lower():find(q, 1, true) then
          total = total + 1
          if shown_n < 10 then
            shown_n = shown_n + 1
            tell(string.format("%s%2d  %s%s", i == now and "\xe2\x96\xb6 " or "  ", i, i == fav and "\xe2\x98\x85 " or "", s.name), false)
          end
        end
      end
      if total == 0 then tell("No station like \"" .. rest .. "\" in " .. head, true)
      elseif total > shown_n then tell("... and " .. (total - shown_n) .. " more: a longer text narrows it", true) end
    end
  elseif sub == "find" or sub == "search" then
    if not dir_base() then return "The station directory is off: /plugin set radio directory (alone: back to the default)" end
    -- words are the name; country:AR (a code or a name), tag:jazz, lang:spanish and min:128 narrow it
    S.country, S.tag, S.lang, S.minbr = nil, nil, nil, nil
    local words = {}
    for w in rest:gmatch("[^ \t\r\n]+") do
      local k, v = w:match("^(%a+):(.+)$")
      k = k and k:lower()
      if k == "country" then S.country = v:match("^%a%a$") and {name = v:upper(), code = v:upper()} or {name = v}
      elseif k == "tag" or k == "genre" then S.tag = v
      elseif k == "lang" or k == "language" then S.lang = v:lower()
      elseif (k == "min" or k == "kbps") and tonumber(v) then S.minbr = math.floor(tonumber(v))
      else words[#words + 1] = w end
    end
    tab = T_SEARCH
    search_for(table.concat(words, " "))
    refresh(true)
  elseif sub == "top" then
    if not dir_base() then return "The station directory is off: /plugin set radio directory (alone: back to the default)" end
    tab = T_BROWSE
    bhome()
    bpush(stations_view("Top voted", "order=votes&reverse=true"))
    refresh(true)
  elseif sub == "save" then
    if not now_st or isekur.radio().state == "off" then return "Nothing is playing" end
    add_to_mine(now_st)
  elseif sub == "add" then
    local url, name = rest:match("^(%S+)%s*(.-)$")
    if not url or not url:match("^https?://") then return "Usage: /radio add <https address> [name]" end
    name = name ~= "" and name or url:match("^https?://([^/]+)")
    local list = mine()
    if #list >= MAX_MINE then return "Mine is full (" .. MAX_MINE .. "): /radio del one first" end
    list[#list + 1] = {name = (name:gsub("[\t\n]", " ")), url = url}
    save_mine(list)
    tell("Added: " .. name .. " (number " .. #stations() .. ")", true)
    refresh()
  elseif sub == "del" then
    local n = find(rest)
    local own = #recs()
    if not n or n <= own then return "Only the stations you added can go: /radio list" end
    local kept = {}
    for i, s in ipairs(mine()) do if i + own ~= n then kept[#kept + 1] = s end end
    save_mine(kept)
    cur = 0
    tell("Removed.", true)
    refresh()
  else
    return "Usage: /radio " .. USAGE
  end
end)

local function back()
  if tab == T_BROWSE and #B.stack > 0 then B.v = table.remove(B.stack); cur = B.v.at or 1; refresh()
  elseif tab == T_SEARCH and S.pick then S.pick = table.remove(S.pstack); cur = S.pick and S.pick.at or 1; refresh() end
end

isekur.on("window", function(e)
  out_tab = {}
  if e.action == "close" then return end
  if e.action == "slider" then
    set_vol(e.value)
    refresh()
    return
  end
  if e.action == "tab" then switch(e.index); return end
  if e.action == "search" then
    if tab == T_SEARCH and not S.pick then search_for(e.text); refresh() end
    return
  end
  if e.action == "back" then back(); return end
  if e.index and e.index > 0 then cur = e.index end
  local ents = entries()
  local s = ents[cur]
  local err
  if e.action == "pick" or e.button == "Play" or e.button == "Open" then
    if s and s.go then s.go() elseif s and not s.note then play_from(ents, cur) end
  elseif e.button == "Random" then err = random_in(ents)
  elseif e.button == "Stop" then stop()
  elseif e.button == "Mute" then err = mute()
  elseif e.button == "Fav" then err = favorite(s)
  elseif e.button == "Add" then if is_station(s) then add_to_mine(s) else err = "Pick a station first" end
  elseif e.button == "Del" then if is_station(s) then del_mine(s) end
  elseif e.button == "Refine" then refine_home()
  elseif e.button == "Back" then back() end
  if err then tell(err, false) end
end)

-- every second: the recommended list when it's due, the window follows what the radio does (tuning, playing, why it stopped), and a station
-- that didn't work in a list gives way to the next one
local sig = ""
isekur.on("tick", function()
  if not fetching and due() then fetch(false) end
  local st = isekur.radio()
  if chain and not pending then
    if st.state == "playing" then chain = nil
    elseif st.state == "off" and st.err ~= "" and now_st then failed(now_st, st.err) end
  end
  if not isekur.window() then return end
  local now = st.state .. st.name .. st.err .. tostring(st.web) .. tostring(st.muted) .. tostring(pending and pending.name)
  if now ~= sig then sig = now; refresh() end
end)
