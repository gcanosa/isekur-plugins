-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- pasteguard: a paste of several lines into a channel or a query goes to a pastebin, and only its link is said, so
-- you don't flood the channel (or get kicked for it). paste.rs by default: no account, the link is unguessable.
-- With it on there, iSekur doesn't ask "Send N lines?" for a paste of chat lines (commands still ask).
-- If the upload fails, nothing is sent: /pasteguard send sends the lines as they are, /pasteguard retry tries again.
isekur.setting("lines", 3, "c", "pastes of this many lines or more become a link; fewer are sent as they are")
isekur.setting("service", "https://paste.rs/", "g", "a URL that takes a POST of the text and answers with the paste's URL")

local pending = {}  -- "<network>\t<tab>" -> the paste that failed to upload

local function count(text) local n = 1 for _ in text:gmatch("\n") do n = n + 1 end return n end

local function upload(srv, tab, text)
  local n = count(text)
  local ok, why = isekur.http(isekur.opt("service", srv, tab), function(r)
    local url = (r.body or ""):match("^%s*(https?://%S+)%s*$")
    if (r.status == 200 or r.status == 201 or r.status == 206) and url then
      pending[srv .. "\t" .. tab] = nil
      isekur.say(srv, tab, url .. " (" .. n .. " lines)")
      if r.status == 206 then isekur.print(srv, tab, "The paste was too long for the pastebin: it has only the start", true) end
    else
      pending[srv .. "\t" .. tab] = text
      isekur.print(srv, tab, "The paste didn't upload (" .. (r.error or "HTTP " .. r.status) .. "), nothing was sent: " ..
                   "/pasteguard send sends its " .. n .. " lines, /pasteguard retry tries again", true)
    end
  end, text .. "\n")
  if not ok then pending[srv .. "\t" .. tab] = text; isekur.print(srv, tab, "Can't upload the paste: " .. why .. ". /pasteguard send sends it as it is", true) end
end

isekur.on("paste", function(e)
  if count(e.text) < isekur.opt("lines", e.srv, e.target) then return end
  upload(e.srv, e.target, e.text)
  return true
end)

isekur.command("pasteguard", "send|retry", function(args, srv, tab)
  local k = (srv or "") .. "\t" .. tab
  local text = pending[k]
  if not text then return "No paste waiting in this tab" end
  if args == "retry" then upload(srv, tab, text)
  elseif args == "send" then pending[k] = nil; isekur.say(srv, tab, text)
  else return "Usage: /pasteguard send (the lines as they are) or /pasteguard retry" end
end)
