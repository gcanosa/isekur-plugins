-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- autosort: keeps the tabs grouped by network, each network's status tab first, then its channels and queries by name, A to Z.
-- The networks keep their order. A tab you /move goes back into place within a second: /plugin disable autosort keeps your order.
isekur.on("tick", function() isekur.sort_tabs() end)
