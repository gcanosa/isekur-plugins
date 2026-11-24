-- version: 1.3
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- dropzone: give iSekur a file and it goes to a file host, and you pick what happens to the link. Drag it onto the webchat (the page shows
-- what letting go does), paste a screenshot there, tap the paperclip on a phone, drop it on the terminal (a path: iSekur takes it when it
-- is a file) or /upload <file>. A box asks first: send the link to this tab, copy it only, or send it to another channel; nothing leaves
-- before you answer, and the box says which third party gets the file (iSekur has nothing to do with it: this plugin only automates the
-- sharing) and takes an optional message that goes before the link. litterbox first (no account, the link goes away after `expire`), uguu when litterbox says no (file hosts often refuse
-- a server's address, and the file leaves from the machine iSekur runs on). The link is public: whoever has it can open the file.
isekur.setting("service", "litterbox uguu", "g", "hosts in order, the next when one says no: litterbox, uguu, catbox, imgur (needs imgur_id) or an https:// address")
isekur.setting("expire", "72h", "g", "litterbox: how long the link lasts", {"1h", "12h", "24h", "72h"})
isekur.setting("action", "ask", "c", "after a drop: ask what to do, send the link to the tab, or only copy it", {"ask", "send", "copy"})
isekur.setting("imgur_id", "", "g", "imgur: your own Client-ID (imgur.com/account/settings/apps)")
isekur.setting("field", "file", "g", "your own address: the name of the form field the file goes in")

local MB = 1048576
local jobs = {}      -- drop id -> {name, size, kind, type, srv, target, svc, acts, ...}
local last_fail      -- {id, act}: what /dropzone retry sends again
local refused = {}   -- host -> until (isekur.time()): it said no to this machine, so it is left out for an hour (no second upload of every file)
local SKIP = 3600

local function human(n)
  if n < 1024 then return n .. " B" elseif n < MB then return ("%.0f KB"):format(n / 1024)
  elseif n < 1024 * MB then return ("%.1f MB"):format(n / MB) else return ("%.2f GB"):format(n / 1024 / MB) end
end

-- where the file goes: the address, the form field, extra fields and headers, the biggest it takes, how long a link lasts
local function one(raw)
  local k = raw:lower()
  if k == "litterbox" then
    local life = isekur.opt("expire")
    return {name = "litterbox", url = "https://litterbox.catbox.moe/resources/internals/api.php", field = "fileToUpload",
            fields = {reqtype = "fileupload", time = life}, max = 1024 * MB, life = life}
  elseif k == "uguu" then
    return {name = "uguu", url = "https://uguu.se/upload?output=text", field = "files[]", fields = {}, max = 128 * MB, life = "3h"}
  elseif k == "catbox" then
    return {name = "catbox", url = "https://catbox.moe/user/api.php", field = "fileToUpload", fields = {reqtype = "fileupload"}, max = 200 * MB}
  elseif k == "imgur" then
    local id = isekur.opt("imgur_id")
    if id == "" then return nil, "imgur needs your own Client-ID: /plugin set dropzone imgur_id <id>" end
    return {name = "imgur", url = "https://api.imgur.com/3/upload", headers = {Authorization = "Client-ID " .. id}, max = 200 * MB,
            kinds = {image = "image", video = "video"}}
  elseif k:match("^https://") then
    return {name = raw:match("^https://([^/:]+)"), url = raw, field = isekur.opt("field"), fields = {}, max = 1024 * MB}
  end
  return nil, "service is litterbox, uguu, catbox, imgur or an https:// address, not " .. raw:sub(1, 40)
end

-- the hosts that can take this file, in the user's order, without the ones that refused this machine lately (all of them again when every one did)
local function services(e)
  local all, why = {}, nil
  for w in isekur.opt("service"):gmatch("%S+") do
    local s, bad = one(w)
    if s then s.host = s.url:match("^https://([^/:]+)") end  -- what the box and the notes call it: the address, not a nickname
    if not s then why = why or bad
    elseif e.size > s.max then why = why or (e.name .. " is " .. human(e.size) .. ": " .. s.name .. " takes " .. human(s.max) .. " at most")
    elseif s.kinds and not s.kinds[e.kind] then why = why or (s.name .. " takes images and video, not " .. e.kind .. " files")
    else all[#all + 1] = s end
  end
  if #all == 0 then return nil, why or "no service is set: /plugin set dropzone service litterbox" end
  local out, skipped, now = {}, {}, isekur.time()
  for _, s in ipairs(all) do
    if (refused[s.name] or 0) > now then skipped[#skipped + 1] = s.host else out[#out + 1] = s end
  end
  if #out == 0 then return all, nil, {} end
  return out, nil, skipped
end

-- the file's address in the host's answer: the text of litterbox and catbox (a paste service's too), imgur's JSON
local function link(svc, body)
  if svc.name == "imgur" then
    local l = body:match('"link"%s*:%s*"([^"]+)"')
    return l and (l:gsub("\\/", "/"))
  end
  local l = body:match("(https?://[^%s\"'<>]+)")
  return l and (l:gsub("[%.,;:!%)]+$", ""))  -- "see https://x/y, thanks"
end

local function note(j, text) isekur.print(j.srv, j.origin or j.target, text, true) end  -- the badge says who

local go
local function finish(id, act, r)
  local j = jobs[id]
  if not j then return end
  local url = r.status >= 200 and r.status < 300 and link(j.svc, r.body or "")
  -- the host says no to this machine (or says nothing): file hosts often refuse a server's or a VPN's address, and the file leaves from where
  -- iSekur runs. That one is remembered (a 413 for a big file, a 500, are about this file or this moment, not this machine)
  local no = r.status == 403 or r.status == 412 or r.status == 429
             or (r.error and (r.error:find("closed the connection", 1, true) or r.error:find("didn't answer", 1, true)))
  if url then refused[j.svc.name] = nil elseif no then refused[j.svc.name] = isekur.time() + SKIP end
  if not url and j.si < #j.svcs and not (r.error and r.error:find("private network", 1, true)) then  -- this host said no: the next one
    note(j, j.svc.host .. " didn't take " .. j.name .. " (" .. (r.error or ("HTTP " .. r.status)) .. "), trying " .. j.svcs[j.si + 1].host .. (j.svcs[j.si + 1].life and " (the link lasts " .. j.svcs[j.si + 1].life .. ")" or "") .. "...")
    j.si = j.si + 1
    j.svc = j.svcs[j.si]
    return go(id, act)
  end
  if not url then
    last_fail = {id = id, act = act}  -- iSekur keeps the file for half an hour
    local body = (r.body or ""):gsub("%s+", " ")
    local why = r.error or ("HTTP " .. r.status .. ": " .. body:match("^ *(.-) *$"):sub(1, 100))
    return note(j, j.name .. " didn't upload (" .. why .. "). /dropzone retry tries again" ..
                (no and ". The file leaves from the machine iSekur runs on, and hosts often refuse a server's address: try another service (/plugin set dropzone service)" or ""))
  end
  jobs[id], last_fail = nil, nil
  local out = (j.msg and j.msg ~= "" and j.msg .. " " or "") .. url  -- the message, if the user typed one, then the link
  if act == "send" then
    isekur.say(j.srv, j.target, out)
    if j.origin and j.origin ~= j.target then note(j, j.name .. " sent to " .. j.target .. ": " .. out) end
  else
    isekur.copy(out)
    note(j, j.name .. ": " .. out .. " (copied)")
  end
end

function go(id, act)
  local j = jobs[id]
  note(j, "sending " .. j.name .. " (" .. human(j.size) .. ") to " .. j.svc.host .. (j.svc.life and ", the link lasts " .. j.svc.life or "") .. "...")
  local s = j.svc
  local ok, why = isekur.upload(id, {url = s.url, field = s.kinds and s.kinds[j.kind] or s.field, fields = s.fields, headers = s.headers, type = j.type},
                                function(r) finish(id, act, r) end)
  if not ok then note(j, j.name .. " can't be sent: " .. why) jobs[id] = nil end
end

local function ask(id)
  local j = jobs[id]
  local hosts = j.svc.host .. (#j.svcs > 1 and " (or " .. j.svcs[2].host .. " if it refuses)" or "")
  local text = {j.name .. " · " .. human(j.size) .. " · " .. j.kind,
                "to " .. j.svc.host .. (j.svc.life and ", the link lasts " .. j.svc.life or ", a public link") ..
                (#j.svcs > 1 and " (" .. j.svcs[2].host .. " if it says no)" or ""),
                "A third party, not iSekur: the file is uploaded to " .. hosts .. ". iSekur has nothing to do with them, this plugin only " ..
                "automates the sharing. Anyone with the link can open the file."}
  if #j.skipped > 0 then text[#text + 1] = table.concat(j.skipped, ", ") .. " said no to this machine a while ago: left out for now" end
  if j.e2e then text[#text + 1] = "!This tab is encrypted. The file will not be." end
  local items, acts = {}, {}
  if j.target then items[#items + 1], acts[#acts + 1] = "Send the link to " .. j.target, "send" end
  items[#items + 1], acts[#acts + 1] = "Copy the link", "copy"
  j.chans = {}
  for _, c in ipairs(j.srv and isekur.channels(j.srv) or {}) do if c ~= j.target then j.chans[#j.chans + 1] = c end end
  if #j.chans > 0 then items[#items + 1], acts[#acts + 1] = "Send it to another channel...", "other" end
  items[#items + 1], acts[#acts + 1] = "Cancel", "cancel"
  j.acts, j.stage = acts, "first"
  isekur.choose{id = id, title = "Send a file", text = text, items = items, input = "Message (optional)"}
end

local function cancel(id) jobs[id] = nil isekur.upload(id, false) end

isekur.on("drop", function(e)
  local list, why, skipped = services(e)
  local j = {name = e.name, size = e.size, kind = e.kind, type = e.type, srv = e.srv, target = e.target, e2e = e.e2e, svcs = list, si = 1, svc = list and list[1],
             skipped = skipped or {}}
  if not list then note(j, why) return cancel(e.id) end
  jobs[e.id] = j
  local act = isekur.opt("action", e.srv, e.target)
  if act == "send" and e.target then return go(e.id, "send") end
  if act == "copy" then return go(e.id, "copy") end
  ask(e.id)
end)

isekur.on("choice", function(e)
  local j = jobs[e.id]
  if not j then return end
  if j.stage == "pick" then  -- the other channel
    local c = j.chans[e.index]
    if not c then return cancel(e.id) end
    j.origin, j.target = j.target, c
    return go(e.id, "send")
  end
  local a = j.acts[e.index] or "cancel"
  j.msg = e.text  -- what the user typed in the box (goes before the link)
  if a == "other" then
    j.stage = "pick"
    local items = {}
    for i = 1, math.min(#j.chans, 7) do items[i] = j.chans[i] end
    items[#items + 1] = "Cancel"
    isekur.choose{id = e.id, title = "Send it to", text = {j.name}, items = items}
  elseif a == "send" or a == "copy" then go(e.id, a)
  else cancel(e.id) end
end)

isekur.command("dropzone", "retry", function(args)
  if args == "retry" then
    if not (last_fail and jobs[last_fail.id]) then return "Nothing to retry" end
    local j = jobs[last_fail.id]
    j.si, j.svc = 1, j.svcs[1]  -- from the first host again
    return go(last_fail.id, last_fail.act)
  end
  return "Usage: /dropzone retry. Drag a file onto the webchat, or /upload <file>, to send one"
end)
