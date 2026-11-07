-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- keepnick: takes your nick back when it's free. While you're on another one (yournick_ because yours was in use
-- when you connected), it asks the server every `every` seconds whether yours is online (ISON, the answer hidden),
-- and right away when you see its holder quit or rename. A /nick you type yourself stops it on that network
-- until you reconnect or /nick back to the one it keeps.
isekur.setting("nick", "", "n", "the nick to keep; empty: the network's nick in your config")
isekur.setting("every", 30, "n", "seconds between checks while you're on another nick; 0: only when you see it go")

local asked, tried, next_at, paused = {}, {}, {}, {}  -- per network: ISON sent, NICK sent, next check, you renamed

local function want(srv)
  local n = isekur.opt("nick", srv)
  if n == "" then n = isekur.nick(srv) or "" end
  return n
end
-- ponytail: lower() is ASCII; a nick that differs only in []\ vs {}| is "another nick" (one extra NICK, harmless)
local function same(a, b) return a and b and a:lower() == b:lower() end
local function missing(srv)
  local w = want(srv)
  return w ~= "" and isekur.me(srv) and not same(isekur.me(srv), w) and not paused[srv] and isekur.opt("enabled", srv)
end
local function grab(srv)
  if not missing(srv) or (tried[srv] or 0) + 5 > isekur.time() then return end  -- at most one try every 5s
  tried[srv] = isekur.time()
  isekur.send(srv, "NICK " .. want(srv))
end

isekur.on("tick", function()
  local now = isekur.time()
  for _, srv in ipairs(isekur.servers()) do
    local every = isekur.opt("every", srv)
    if missing(srv) and every > 0 and now >= (next_at[srv] or 0) then
      next_at[srv], asked[srv] = now + every, now
      isekur.send(srv, "ISON " .. isekur.me(srv) .. " " .. want(srv))  -- you first: tells our answer from /notify's
    end
  end
end)

isekur.on("raw", function(e)
  if e.cmd == "303" and asked[e.srv] and asked[e.srv] + 30 > isekur.time() then
    local on = {}
    for n in (e.args:match(":(.*)$") or ""):gmatch("%S+") do on[#on + 1] = n end
    if not same(on[1], isekur.me(e.srv)) then return end  -- not ours: /notify's ISON
    asked[e.srv] = nil
    local taken = false
    for _, n in ipairs(on) do taken = taken or same(n, want(e.srv)) end
    if not taken then grab(e.srv) end
    return true
  end
  -- what the server says to our NICK: in use, held by services for a while, too many changes
  if (e.cmd == "433" or e.cmd == "437" or e.cmd == "438") and tried[e.srv] and tried[e.srv] + 10 > isekur.time() then
    return true
  end
end)

local function gone(e) if same(e.nick, want(e.srv)) and not e.self then grab(e.srv) end end
isekur.on("quit", gone)
isekur.on("nick", function(e)
  if e.self then
    if same(e.new, want(e.srv)) then
      isekur.print(e.srv, nil, "You have your nick back: " .. e.new, true)
      tried[e.srv] = nil
    end
    return
  end
  gone(e)
end)
isekur.on("command", function(e)
  if e.name ~= "nick" or not e.srv then return end
  local to = e.args:match("^%s*(%S+)")
  paused[e.srv] = to and not same(to, want(e.srv)) or nil
end)
isekur.on("connect", function(e) paused[e.srv], tried[e.srv], next_at[e.srv], asked[e.srv] = nil, nil, nil, nil end)
