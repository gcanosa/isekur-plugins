-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- pmguard: private messages from people you haven't let through are held, not opened in a tab: spam and bots stay
-- out. You're told once per nick in the network's tab; /pmguard allow nick opens the query with what they said.
-- People you /msg or /query yourself are let through, and so are services (NickServ...) and notices.
isekur.setting("channels", false, "n", "let through people who share a channel with you")
isekur.setting("reply", "", "n", "a notice sent once to whoever's held (empty: none; an answer tells a spammer you're there)")

local held = {}   -- "<network>\t<nick lowercased>" -> {nick =, lines = {...}}
local told = {}   -- the same keys: told about, and replied to, this session
local order = {}  -- held keys, oldest first: 50 nicks at most
local MAX_LINES, MAX_NICKS = 20, 50

local function key(srv, nick) return srv .. "\t" .. nick:lower() end
local function allowed(srv, nick) return isekur.store_get("a\t" .. key(srv, nick)) ~= nil end
local function allow(srv, nick) isekur.store_set("a\t" .. key(srv, nick), nick) end

local function drop(k)
  held[k] = nil
  for i, o in ipairs(order) do if o == k then table.remove(order, i) break end end
end

local function shared(srv, nick)
  for _, ch in ipairs(isekur.channels(srv)) do if isekur.rank(srv, ch, nick) then return true end end
end

isekur.on("message", function(e)
  if e.self or e.notice or isekur.is_chan(e.srv, e.target) or not e.opened then return end  -- a tab already open: you're talking
  local nick = e.nick
  if nick:find("[%.%*]") or nick:lower():match("serv$") or allowed(e.srv, nick) then return end  -- a server, *status, services
  if isekur.opt("channels", e.srv) and shared(e.srv, nick) then return end
  local k = key(e.srv, nick)
  local h = held[k]
  if not h then
    if #order >= MAX_NICKS then drop(order[1]) end
    h = {nick = nick, lines = {}}
    held[k], order[#order + 1] = h, k
  end
  if #h.lines < MAX_LINES then
    h.lines[#h.lines + 1] = isekur.date(nil, "%H:%M") .. " " .. (e.action and "* " .. nick .. " " or "<" .. nick .. "> ") .. e.text
  end
  if not told[k] then
    told[k] = true
    isekur.print(e.srv, nil, "Held a private message from " .. nick .. ": /pmguard allow " .. nick ..
                 " opens it, /pmguard show " .. nick .. " shows it here", true)
    local r = isekur.opt("reply", e.srv)
    if r ~= "" then isekur.send(e.srv, "NOTICE " .. nick .. " :" .. r) end
  end
  return true
end)

-- you write to them first: they're let through
isekur.on("command", function(e)
  if not e.srv or (e.name ~= "msg" and e.name ~= "query" and e.name ~= "q") then return end
  local to = e.args:match("^%s*(%S+)")
  if to and to:sub(1, 1) ~= "-" and not isekur.is_chan(e.srv, to) and not to:find(",") then allow(e.srv, to) end
end)
isekur.on("nick", function(e) if allowed(e.srv, e.nick) then allow(e.srv, e.new) end end)

isekur.command("pmguard", "[allow|deny|show|drop nick | allowed]", function(args, srv, tab)
  if not srv then return "Use /pmguard in a network's tab" end
  local what, nick = args:match("^%s*(%S*)%s*(%S*)")
  local k = nick ~= "" and key(srv, nick)
  local h = k and held[k]
  if what == "" then
    local n = 0
    for _, o in ipairs(order) do
      local x = held[o]
      if o:match("^([^\t]*)") == srv then
        n = n + 1
        isekur.print(srv, tab, x.nick .. ": " .. #x.lines .. " held, the first " .. x.lines[1])
      end
    end
    if n == 0 then isekur.print(srv, tab, "Nobody held on " .. srv .. ". /pmguard allowed lists who's let through") end
  elseif what == "allowed" then
    local list = {}
    for _, sk in ipairs(isekur.store_keys()) do
      local s = sk:match("^a\t([^\t]*)\t")
      if s == srv then list[#list + 1] = isekur.store_get(sk) end
    end
    table.sort(list)
    isekur.print(srv, tab, #list > 0 and "Let through on " .. srv .. ": " .. table.concat(list, " ") or "Nobody let through on " .. srv .. " yet")
  elseif what == "allow" and nick ~= "" then
    allow(srv, h and h.nick or nick)
    if h then
      isekur.exec(srv, tab, "/query " .. h.nick)
      for _, l in ipairs(h.lines) do isekur.print(srv, h.nick, l) end
      drop(k)
    else
      isekur.print(srv, tab, nick .. " is let through from now on")
    end
  elseif what == "show" and nick ~= "" then
    if not h then return "Nothing held from " .. nick end
    for _, l in ipairs(h.lines) do isekur.print(srv, tab, l) end
  elseif (what == "deny" or what == "drop") and nick ~= "" then
    if what == "deny" then isekur.store_set("a\t" .. k, nil) end
    drop(k)
    isekur.print(srv, tab, what == "deny" and nick .. " is held again from now on" or "Dropped what " .. nick .. " said")
  else
    return "Usage: /pmguard, /pmguard allow|show|drop|deny nick, /pmguard allowed"
  end
end)
