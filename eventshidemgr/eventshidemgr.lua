-- version: 1.1
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- eventshidemgr.lua: runs of joins, parts, quits and nick changes folded into one row, "3 joined, 2 left" with a mark that turns when it is open.
-- A click opens the run and a click folds it again; so does leaving the tab. In the terminal and the webchat.
-- On your screens only: the logs and the scrollback keep every line. Kicks, your own joins and parts and every
-- message end a run, and a lone join stays a normal line.
isekur.setting("names", false, "c", "name who joined, left or renamed in the row: 3 joined (a, b, +1)")
isekur.setting("nicks", true, "c", "count nick changes too (renamed); off leaves them as plain lines")
isekur.setting("quiet", "hide", "c", "in a /quiet tab: hide shows nothing, as /quiet always did; fold keeps the summary rows there (click to see the lines)", {"hide", "fold"})

-- the program does the folding and the drawing; the plugin only turns it on, where it is enabled, and gives it the
-- settings above. It ends with the plugin (disabled, removed, reloaded)
isekur.fold(true)
