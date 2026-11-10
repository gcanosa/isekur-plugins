-- version: 1.1
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- autosort: keeps the tabs grouped by network, each network's status tab first, then its channels and queries by name, A to Z.
-- The networks keep their order. A tab you /move (or drag) stays where you put it, the others sort around it, until iSekur restarts.
isekur.on("tick", function() isekur.sort_tabs() end)
