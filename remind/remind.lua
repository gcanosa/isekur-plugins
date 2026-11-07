-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- remind: /remind 10m check the build, /remind 1h30m ..., /remind 18:30 call home. The reminder shows in the tab
-- you set it in (and the one you're on). They're saved: one due while iSekur was off shows when it starts.
-- /remind alone lists them, /remind del 2 removes one.

-- the store: "r<id>" -> "<due>\t<network or empty>\t<tab>\t<text>", "next" -> the next id
local function parse(v)
  local due, srv, tab, text = v:match("^(%d+)\t([^\t]*)\t([^\t]*)\t(.*)$")
  return due and {due = tonumber(due), srv = srv ~= "" and srv or nil, tab = tab, text = text}
end
local function all()
  local out = {}
  for _, k in ipairs(isekur.store_keys()) do
    local id = k:match("^r(%d+)$")
    local r = id and parse(isekur.store_get(k))
    if r then r.id = tonumber(id); out[#out + 1] = r end
  end
  table.sort(out, function(a, b) return a.due < b.due end)
  return out
end

local function left(s)
  if s < 60 then return s .. "s" end
  local d, h, m = s // 86400, s % 86400 // 3600, s % 3600 // 60
  if d > 0 then return d .. "d" .. (h > 0 and h .. "h" or "") end
  return (h > 0 and h .. "h" or "") .. (m > 0 and m .. "m" or "")
end

-- "10m", "1h30m", "2d", "90s", "1w" or "18:30" (the next one): seconds from now, or nil
local function when(spec, now)
  local hh, mm = spec:match("^(%d%d?):(%d%d)$")
  if hh then
    hh, mm = tonumber(hh), tonumber(mm)
    if hh > 23 or mm > 59 then return nil end
    local H, M, S = isekur.date(now, "%H %M %S"):match("(%d+) (%d+) (%d+)")
    local t = hh * 3600 + mm * 60 - (tonumber(H) * 3600 + tonumber(M) * 60 + tonumber(S))
    return t > 0 and t or t + 86400  -- ponytail: a DST change that night moves it an hour
  end
  if not spec:match("^[%dsmhdw]+$") or not spec:match("^%d") then return nil end
  local unit, total = {s = 1, m = 60, h = 3600, d = 86400, w = 604800}, 0
  for n, u in spec:gmatch("(%d+)([smhdw])") do total = total + tonumber(n) * unit[u] end
  if spec:gsub("%d+[smhdw]", "") ~= "" then return nil end
  return total > 0 and total or nil
end

local function show(r, late)
  local text = "Reminder: " .. r.text .. (late and " (it was due " .. isekur.date(r.due, "%a %H:%M") .. ")" or "")
  isekur.print(r.srv, r.tab, text, true)
  local as, at = isekur.active()
  if as ~= r.srv or at ~= r.tab then isekur.print(as, at, text, true) end
end

local started = false
isekur.on("tick", function()
  local now = isekur.time()
  for _, r in ipairs(all()) do
    if r.due > now then break end
    isekur.store_set("r" .. r.id, nil)
    show(r, not started and now - r.due > 60)
  end
  started = true
end)

isekur.command("remind", "[10m|1h30m|18:30 text | del n]", function(args, srv, tab)
  local now = isekur.time()
  local list = all()
  if args:match("^%s*$") then
    if #list == 0 then isekur.print(srv, tab, "No reminders. /remind 10m text, /remind 18:30 text") return end
    for i, r in ipairs(list) do
      isekur.print(srv, tab, i .. ". in " .. left(math.max(0, r.due - now)) .. " (" .. isekur.date(r.due, "%a %H:%M") .. ") in " ..
                   (r.srv and r.srv .. "/" or "") .. r.tab .. ": " .. r.text)
    end
    return
  end
  local del = args:match("^%s*del%s+(%d+)%s*$")
  if del then
    local r = list[tonumber(del)]
    if not r then return "No reminder " .. del .. ": /remind lists them" end
    isekur.store_set("r" .. r.id, nil)
    isekur.print(srv, tab, "Removed: " .. r.text)
    return
  end
  local spec, text = args:match("^%s*(%S+)%s+(.-)%s*$")
  local secs = spec and when(spec:lower(), now)
  if not secs or text == "" then return "Usage: /remind 10m text, /remind 1h30m text, /remind 18:30 text, /remind del n" end
  local id = tonumber(isekur.store_get("next") or "1")
  isekur.store_set("next", tostring(id + 1))
  isekur.store_set("r" .. id, (now + secs) .. "\t" .. (srv or "") .. "\t" .. tab .. "\t" .. text)
  isekur.print(srv, tab, "I'll remind you in " .. left(secs) .. " (" .. isekur.date(now + secs, "%a %H:%M") .. ")")
end)
