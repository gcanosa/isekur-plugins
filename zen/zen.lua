-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- zen: /zen hides the tabs, the nicklist, the topic and the status bar and leaves only the chat, in a column in the
-- middle, the last few lines bright and the ones before them dimmed, in a calm black-and-grey theme. /zen again or Esc
-- on an empty line brings everything back; so does disabling or removing the plugin. The theme is never saved.
isekur.setting("where", "both", "g", "where /zen turns it on", {"both", "terminal", "web"})
isekur.setting("theme", "mono", "g", "the theme while it's on; keep: the one you use", {"mono", "mono-light", "keep"})
isekur.setting("lines", 5, "g", "the last lines kept bright; the ones before them are dimmed")
isekur.setting("width", 80, "g", "the chat column's width, in characters")
isekur.setting("events", false, "g", "show joins, parts, quits and nick changes")

isekur.command("zen", "", function()
  if not isekur.view then return "zen needs a newer iSekur" end
  if isekur.view() then isekur.view(false); return end
  local where, th = isekur.opt("where"), isekur.opt("theme")
  local ok, err = isekur.view{
    term = where ~= "web", web = where ~= "terminal",
    theme = th ~= "keep" and th or nil,
    lines = isekur.opt("lines"), width = isekur.opt("width"), events = isekur.opt("events"),
  }
  if not ok then return "zen: " .. err end
end)
