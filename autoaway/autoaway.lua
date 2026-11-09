-- version: 1.4
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- autoaway: away when nobody is attached (no terminal, webchat or BNC client) or after `idle`
-- minutes without typing, whichever comes first; back when you return. A manual /away is left alone.
-- With idle = 0 the nobody-attached rule is 30s (--daemon with no browser open).
isekur.setting("idle", 0, "n", "minutes without typing, or with nothing attached; 0: nothing attached for 30s")
isekur.setting("message", "Not here right now", "n", "the away message others see")
isekur.setting("announce_away", false, "c", "say \"/me is away: <message>\" in your channels (many dislike it)")
isekur.setting("announce_back", false, "c", "say \"/me is back\" in your channels when you return")

local mine = {}  -- network -> true: we set that away

local function announce(srv, key, text)
  for _, ch in ipairs(isekur.channels(srv)) do
    if isekur.opt(key, srv, ch) then isekur.exec(srv, ch, "/me " .. text) end
  end
end

isekur.on("tick", function()
  local nobody = not isekur.attached()
  local gone = isekur.detached_for()  -- seconds since the last console or webchat left (0 while one is attached)
  local live = {}
  for _, srv in ipairs(isekur.servers()) do
    live[srv] = true
    local idle = isekur.opt("idle", srv)
    local limit = idle > 0 and idle * 60 or 30  -- the same minutes for both rules; 30s when idle is 0
    local want = isekur.opt("enabled", srv) and ((nobody and gone >= limit) or (idle > 0 and isekur.idle() >= idle * 60))
    if want and not isekur.away(srv) and not mine[srv] then
      mine[srv] = true
      local msg = isekur.opt("message", srv)
      isekur.send(srv, "AWAY :" .. msg)
      announce(srv, "announce_away", "is away: " .. msg)
    elseif not want and mine[srv] and isekur.away(srv) then
      mine[srv] = nil
      isekur.send(srv, "AWAY")
      announce(srv, "announce_back", "is back")
    end
  end
  for srv in pairs(mine) do if not live[srv] then mine[srv] = nil end end  -- disconnected: not away any more
end)

-- the server says you're back (whoever asked), or you typed /away or /back: yours from now on
isekur.on("away", function(e) if not e.away then mine[e.srv] = nil end end)
isekur.on("command", function(e) if e.srv and (e.name == "away" or e.name == "back") then mine[e.srv] = nil end end)
