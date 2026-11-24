-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- dropzone: give iSekur a file and it goes to a file host, and you pick what happens to the link. Drag it onto the webchat (the page shows
-- what letting go does), paste a screenshot there, tap the paperclip on a phone, drop it on the terminal (a path: iSekur takes it when it
-- is a file) or /upload <file>. A box asks first: send the link to this tab, copy it only, or send it to another channel; nothing leaves
-- before you answer. litterbox by default (no account, the link goes away after `expire`): the link is public, whoever has it can open it.
isekur.setting("service", "litterbox", "g", "litterbox (link expires), catbox (kept), imgur (images; needs imgur_id) or your own https:// address")
isekur.setting("expire", "72h", "g", "litterbox: how long the link lasts", {"1h", "12h", "24h", "72h"})
isekur.setting("action", "ask", "c", "after a drop: ask what to do, send the link to the tab, or only copy it", {"ask", "send", "copy"})
isekur.setting("imgur_id", "", "g", "imgur: your own Client-ID (imgur.com/account/settings/apps)")
isekur.setting("field", "file", "g", "your own address: the name of the form field the file goes in")

local MB = 1048576
local jobs = {}      -- drop id -> {name, size, kind, type, srv, target, svc, acts, ...}
local last_fail      -- {id, act}: what /dropzone retry sends again

local function human(n)
  if n < 1024 then return n .. " B" elseif n < MB then return ("%.0f KB"):format(n / 1024)
  elseif n < 1024 * MB then return ("%.1f MB"):format(n / MB) else return ("%.2f GB"):format(n / 1024 / MB) end
end

-- where the file goes: the address, the form field, extra fields and headers, the biggest it takes, how long a link lasts
local function service()
  local raw = isekur.opt("service")
  local k = raw:lower()
  if k == "litterbox" then
    local life = isekur.opt("expire")
    return {name = "litterbox", url = "https://litterbox.catbox.moe/resources/internals/api.php", field = "fileToUpload",
            fields = {reqtype = "fileupload", time = life}, max = 1024 * MB, life = life}
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
  return nil, "service is litterbox, catbox, imgur or an https:// address, not " .. raw:sub(1, 40)
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

local function finish(id, act, r)
  local j = jobs[id]
  if not j then return end
  local url = r.status >= 200 and r.status < 300 and link(j.svc, r.body or "")
  if not url then
    last_fail = {id = id, act = act}  -- iSekur keeps the file for half an hour
    local body = (r.body or ""):gsub("%s+", " ")
    local why = r.error or ("HTTP " .. r.status .. ": " .. body:match("^ *(.-) *$"):sub(1, 100))
    return note(j, j.name .. " didn't upload (" .. why .. "). /dropzone retry tries again")
  end
  jobs[id], last_fail = nil, nil
  if act == "send" then
    isekur.say(j.srv, j.target, url)
    if j.origin and j.origin ~= j.target then note(j, j.name .. " sent to " .. j.target .. ": " .. url) end
  else
    isekur.copy(url)
    note(j, j.name .. ": " .. url .. " (copied)")
  end
end

local function go(id, act)
  local j = jobs[id]
  note(j, "sending " .. j.name .. " (" .. human(j.size) .. ") to " .. j.svc.name .. "...")
  local s = j.svc
  local ok, why = isekur.upload(id, {url = s.url, field = s.kinds and s.kinds[j.kind] or s.field, fields = s.fields, headers = s.headers, type = j.type},
                                function(r) finish(id, act, r) end)
  if not ok then note(j, j.name .. " can't be sent: " .. why) jobs[id] = nil end
end

local function ask(id)
  local j = jobs[id]
  local text = {j.name .. " · " .. human(j.size) .. " · " .. j.kind,
                "to " .. j.svc.name .. (j.svc.life and ", the link lasts " .. j.svc.life or ", a public link")}
  if j.e2e then text[#text + 1] = "!This tab is encrypted. The file will not be." end
  local items, acts = {}, {}
  if j.target then items[#items + 1], acts[#acts + 1] = "Send the link to " .. j.target, "send" end
  items[#items + 1], acts[#acts + 1] = "Copy the link only", "copy"
  j.chans = {}
  for _, c in ipairs(j.srv and isekur.channels(j.srv) or {}) do if c ~= j.target then j.chans[#j.chans + 1] = c end end
  if #j.chans > 0 then items[#items + 1], acts[#acts + 1] = "Send it to another channel...", "other" end
  items[#items + 1], acts[#acts + 1] = "Cancel", "cancel"
  j.acts, j.stage = acts, "first"
  isekur.choose{id = id, title = "Send a file", text = text, items = items}
end

local function cancel(id) jobs[id] = nil isekur.upload(id, false) end

isekur.on("drop", function(e)
  local svc, why = service()
  local j = {name = e.name, size = e.size, kind = e.kind, type = e.type, srv = e.srv, target = e.target, e2e = e.e2e, svc = svc}
  if not svc then note(j, why) return cancel(e.id) end
  if e.size > svc.max then note(j, e.name .. " is " .. human(e.size) .. ": " .. svc.name .. " takes " .. human(svc.max) .. " at most") return cancel(e.id) end
  if svc.kinds and not svc.kinds[e.kind] then note(j, svc.name .. " takes images and video, not " .. e.kind .. " files") return cancel(e.id) end
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
    return go(last_fail.id, last_fail.act)
  end
  return "Usage: /dropzone retry. Drag a file onto the webchat, or /upload <file>, to send one"
end)
