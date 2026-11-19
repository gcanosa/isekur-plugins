-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- nickcolors.lua: nicks in the colors the chat gives them: the nicks said inside a message, and/or the user list.
-- On your screens only: nothing is sent in color and the logs keep the plain text. Your own nick is the theme's own
-- color for you (/set own_nick_color).
isekur.setting("where", "both", "g", "where the nicks get their colors: in what people say, in the user list, or both", {"both", "chat", "userlist"})
isekur.setting("min", 3, "g", "nicks shorter than this many letters stay plain in a message, or every 'al' and 'jo' would be a name")

local NICK = "[%w%[%]\\`_^{|}%-]+"  -- what a nick is made of (the same letters the webchat underlines)

-- the nicks of the channel (or the two of a query) said in the text, each in its own color. Text that has colors of its
-- own is left alone, and so is a link or a #channel
local function paint(e)
  local text, out, at, last = e.text, {}, 1, 1
  if text:find("[\3\4]") then return end
  local chan = isekur.is_chan(e.srv, e.target)
  local min = isekur.opt("min")
  local me = isekur.me(e.srv)
  while true do
    local s, f = text:find(NICK, at)
    if not s then break end
    at = f + 1
    local word, before, after = text:sub(s, f), text:sub(s - 1, s - 1), text:sub(f + 1, f + 2)
    -- part of a link (its word has "://"), or a name like #bob or bob.com
    local from, to = text:sub(1, s - 1):find("[^%s]*$"), text:find("%s", f + 1) or #text + 1
    local plain = text:sub(from, to - 1):find("://", 1, true) or before:find("^[#&/.]") or after:find("^%.%w") or #word < min
    if not plain then
      local who = chan and isekur.rank(e.srv, e.target, word) ~= nil
        or not chan and (word:lower() == e.target:lower() or (me and word:lower() == me:lower()))
      local c = who and isekur.nick_color(e.srv, word)
      if c then
        out[#out + 1] = text:sub(last, s - 1) .. string.format("\4%06x", c) .. word .. "\4"
        last = f + 1
      end
    end
  end
  if last == 1 then return end
  return table.concat(out) .. text:sub(last)
end

isekur.on("show", function(e)
  if isekur.opt("where") ~= "userlist" then return paint(e) end
end)

-- the user list is the program's own: ask it to paint, and keep it in step with the setting (it paints only where
-- the plugin is on, and stops when it goes)
local function userlist()
  local want = isekur.opt("where") ~= "chat"
  if want ~= isekur.nicklist_colors() then isekur.nicklist_colors(want) end
end
userlist()
isekur.on("tick", userlist)
