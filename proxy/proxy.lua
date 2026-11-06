-- version: 1.0
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- proxy: connect a network through a SOCKS4/SOCKS5 or HTTP proxy, or an SSH jump host, the others stay direct.
-- Set the url on the networks that need it:
--   /plugin set proxy@sekurnet url socks5://127.0.0.1:9050        (Tor: the proxy resolves the names)
--   /plugin set proxy@work url http://me:secret@proxy.lan:3128
--   /plugin set proxy@other url ssh://me@jump.example.org:22       (ssh -W: keys or an agent, no password prompt)
-- A url set without @network applies to every network that has none of its own.
-- Then /reconnect there. If the plugin is off, removed or broken, connections go direct.
isekur.setting("url", "", "n", "socks5://[user:pass@]host[:1080], socks4://, http://[user:pass@]host[:8080], ssh://[user@]host[:22]; empty: direct")

isekur.on("connect", function(e)
  local url = isekur.opt("url", e.srv)
  if url ~= "" then isekur.proxy(e.srv, url) end
end)
