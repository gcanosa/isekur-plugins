-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- push: your highlights and private messages sent to your phone, tablet or browser while you're away
-- or nothing is attached. ntfy (no account: install the ntfy app or open ntfy.sh in a browser, subscribe
-- to a topic, /plugin set push topic <it>) or a Telegram bot (token + chat). /push test checks it.
-- A channel or network goes quiet with /plugin disable push@net/#chan.
isekur.setting("service", "ntfy", "g", "ntfy or telegram")
isekur.setting("topic", "", "g", "ntfy topic: hard to guess, anyone who knows it reads your pushes")
isekur.setting("server", "https://ntfy.sh", "g", "ntfy server, if you run your own")
isekur.setting("token", "", "g", "telegram bot token (from @BotFather)")
isekur.setting("chat", "", "g", "telegram chat id (yours: message the bot, then ask @userinfobot)")
isekur.setting("always", false, "g", "push even while you're here and attached")
isekur.setting("pms", true, "n", "push private messages")
isekur.setting("max", 10, "g", "pushes a minute at most (the rest are dropped)")

local sent, minute, warned = 0, 0, false

local function enc(s)
  return (s:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function strip(s)  -- mIRC colors and formatting
  return (s:gsub("\3%d?%d?,?%d?%d?", ""):gsub("[\2\15\22\29\30\31]", ""))
end

local function url(title, text)
  if isekur.opt("service") == "telegram" then
    local tok, chat = isekur.opt("token"), isekur.opt("chat")
    if tok == "" or chat == "" then return nil, "set token and chat: /plugin set push token ..." end
    return "https://api.telegram.org/bot" .. tok .. "/sendMessage?chat_id=" .. enc(chat) .. "&text=" .. enc(title .. "\n" .. text)
  end
  local topic = isekur.opt("topic")
  if topic == "" then return nil, "set a topic: /plugin set push topic <something hard to guess>" end
  -- ponytail: ntfy's GET /publish, isekur.http has no POST; fine for IRC-sized lines
  return isekur.opt("server"):gsub("/+$", "") .. "/" .. enc(topic) .. "/publish?title=" .. enc(title) ..
         "&message=" .. enc(text) .. "&tags=speech_balloon"
end

local function push(title, text, srv, target)
  local u, why = url(title, text)
  if not u then return why end
  isekur.http(u, function(r)
    if r.status == 200 then warned = false; return end
    if not warned or srv then  -- one error per failure streak, unless it's /push test
      isekur.print(srv, target, "push failed: " .. (r.error ~= "" and r.error or "HTTP " .. r.status), true)
    end
    warned = true
  end)
end

isekur.on("message", function(e)
  if e.self or not e.hilight then return end
  local chan = isekur.is_chan(e.srv, e.target)
  if not chan and not isekur.opt("pms", e.srv) then return end
  if not isekur.opt("always") and isekur.attached() and not isekur.away(e.srv) then return end
  local m = math.floor(isekur.time() / 60)
  if m ~= minute then minute, sent = m, 0 end
  sent = sent + 1
  if sent > isekur.opt("max") then return end
  local title = chan and e.nick .. " in " .. e.target .. " (" .. e.srv .. ")" or e.nick .. " (" .. e.srv .. ")"
  push(title, (e.action and "* " .. e.nick .. " " or "") .. strip(e.text))
end)

isekur.command("push", "test", function(args, srv, target)
  if args ~= "test" then return "Usage: /push test" end
  local why = push("iSekur", "push works", srv, target)
  if why then return why end
  isekur.print(srv, target, "push: test sent", true)
end)
