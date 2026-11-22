-- version: 1.2
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- eventshidemgr.lua: runs of joins, parts, quits and other events folded into one row, "3 joined, 2 left, 1 mode set" with a mark that turns when it is open.
-- A click opens the run and a click folds it again; so does leaving the tab. In the terminal and the webchat.
-- Which events fold is yours to pick, one setting each: joins, leaves, nicks (on), hosts (hostname changes), modes, kicks and topics (off until you
-- switch them on). One that doesn't fold stays a plain line and ends a run. On your screens only: the logs and the scrollback keep every line.
-- Your own events and every message end a run, and a lone event stays a normal line.
isekur.setting("names", false, "c", "name who is in the row: 3 joined (a, b, +1)")
isekur.setting("joins", true, "c", "fold joins (joined); off leaves them as plain lines")
isekur.setting("leaves", true, "c", "fold parts and quits (left); off leaves them as plain lines")
isekur.setting("nicks", true, "c", "fold nick changes (renamed); off leaves them as plain lines")
isekur.setting("hosts", false, "c", "fold hostname changes (host changed); they only show as lines where this is on")
isekur.setting("modes", false, "c", "fold channel mode changes (mode set); /quiet hides these too")
isekur.setting("kicks", false, "c", "fold kicks (kicked); off leaves each one as a line")
isekur.setting("topics", false, "c", "fold topic changes (topic changed); off leaves each one as a line")
isekur.setting("quiet", "hide", "c", "in a /quiet tab: hide shows nothing, as /quiet always did; fold keeps the summary rows there (click to see the lines)", {"hide", "fold"})

-- the program does the folding and the drawing; the plugin only turns it on, where it is enabled, and gives it the
-- settings above. It ends with the plugin (disabled, removed, reloaded)
isekur.fold(true)
