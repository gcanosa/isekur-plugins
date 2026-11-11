-- version: 2.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- pmguard: private messages from people you haven't let through are held, not opened in a tab: spam and bots stay
-- out. You're told once per nick in the network's tab; /pmguard allow nick opens the query with what they said.
-- People you /msg or /query yourself are let through, and so are services (NickServ...) and notices.
-- The nicklist's right click (and a query tab's) gets "Allow PMs" or "Remove from PM list" where it's on.
-- Who's let through is the "allowed" setting, per network: /plugin's window shows and edits it (terminal and webchat).
isekur.setting("channels", false, "n", "let through people who share a channel with you")
isekur.setting("reply", "I don't take private messages from people I haven't added yet. Say hi in a channel first.", "n",
               "a notice sent once to whoever's held (empty: none; an answer tells a spammer you're there)")
isekur.setting("allowed", "", "n", "nicks let through, separated by spaces (everywhere's apply where a network has none)")

local held = {}   -- "<network>\t<nick lowercased>" -> {nick =, lines = {...}}
local told = {}   -- the same keys: told about, and replied to, this session
local order = {}  -- held keys, oldest first: 50 nicks at most
local MAX_LINES, MAX_NICKS = 20, 50

local function key(srv, nick) return srv .. "\t" .. nick:lower() end
local function at(l, nick)
  for i, n in ipairs(l) do if n:lower() == nick:lower() then return i end end
end
local moved = {}  -- networks whose list from 1.1 (the store's "a\t<net>\t<nick>") went into the setting
local function list(srv)
  local l = {}
  for n in isekur.opt("allowed", srv):gmatch("%S+") do l[#l + 1] = n end
  if not moved[srv] then
    moved[srv] = true
    local was = #l
    for _, sk in ipairs(isekur.store_keys()) do
      if sk:match("^a\t([^\t]*)\t") == srv then
        local n = isekur.store_get(sk)
        if not at(l, n) then l[#l + 1] = n end
        isekur.store_set(sk, nil)
      end
    end
    if #l > was then isekur.set("allowed", table.concat(l, " "), srv) end
  end
  return l
end
local function allowed(srv, nick) return at(list(srv), nick) ~= nil end
local function allow(srv, nick)
  local l = list(srv)
  if not at(l, nick) then l[#l + 1] = nick isekur.set("allowed", table.concat(l, " "), srv) end
end
local function deny(srv, nick)  -- ponytail: emptying a network's list falls back to everywhere's
  local l = list(srv)
  local i = at(l, nick)
  if i then table.remove(l, i) isekur.set("allowed", table.concat(l, " "), srv) end
end

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
  if not to or to:sub(1, 1) == "-" or isekur.is_chan(e.srv, to) or to:find(",") or allowed(e.srv, to) then return end
  allow(e.srv, to)
  -- run it ourselves so the note lands after it, in the query tab /query opened (a /msg's line stays where you typed)
  isekur.exec(e.srv, e.target, "/" .. e.name .. " " .. e.args)
  isekur.print(e.srv, e.name == "msg" and e.target or to, "You started this conversation, so " .. to ..
               " can reply: pmguard lets their private messages through (/pmguard deny " .. to .. " undoes it)", true)
  return true
end)
isekur.on("nick", function(e) if allowed(e.srv, e.nick) then allow(e.srv, e.new) end end)

isekur.on("nickmenu", function(e)
  local nick = e.nick
  if nick == isekur.me(e.srv) or nick:find("[%.%*]") or nick:lower():match("serv$") then return end
  if allowed(e.srv, nick) then return {{"Remove from PM list", "/pmguard deny " .. nick}} end
  return {{"Allow PMs", "/pmguard allow " .. nick}}
end)

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
    local l = list(srv)
    table.sort(l, function(a, b) return a:lower() < b:lower() end)
    isekur.print(srv, tab, (#l > 0 and "Let through on " .. srv .. ": " .. table.concat(l, " ") or "Nobody let through on " .. srv .. " yet") ..
                 " (/plugin, pmguard's allowed, edits it)")
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
    if what == "deny" then deny(srv, nick) end
    drop(k)
    isekur.print(srv, tab, what == "deny" and nick .. " is held again from now on" or "Dropped what " .. nick .. " said")
  else
    return "Usage: /pmguard, /pmguard allow|show|drop|deny nick, /pmguard allowed"
  end
end)
