# iSekur plugins

The plugin catalog of [iSekur](https://github.com/gcanosa/iSekur), the terminal IRC client with a
built-in webchat. Nothing here is installed by default: in iSekur, `/plugin` opens the plugin
window (or the puzzle button in the webchat), and `/plugin install name` fetches one from here,
checks its sha256 against `index.json`, and turns it on.

| Plugin | What it does |
|---|---|
| **autoaway** | Away when you're idle or nothing is attached, back when you return; on or off per network, away and back announced if you like. |
| **awaylog** | Your highlights and private messages while you were away or detached, summed up in each network's console when you come back, with a pointer in the tab you're on. |
| **keepnick** | Takes your nick back once it's free: when you see its holder leave, and by asking the server every 30 seconds (`every`). A `/nick` you type yourself stops it on that network until you reconnect. |
| **pasteguard** | A paste of 3 lines or more (`lines`) into a channel or a query goes to a pastebin (paste.rs by default, `service`) and only its link is said. If the upload fails nothing is sent: `/pasteguard send` or `/pasteguard retry`. |
| **pmguard** | Private messages from people you haven't let through are held, not opened: you're told once, `/pmguard allow nick` opens the query with what they said. People you `/msg` yourself, services and notices go through; `channels on` lets in people who share a channel with you. |
| **preview** | Under links people post, in the webchat: a card with the page's title, description and picture, the picture itself for image links, and a player for audio and video links (mp3, ogg, m4a, mp4, webm...). In the terminal, the title and description as text. |
| **push** | Your highlights and private messages pushed to your phone, tablet or browser while you're away or nothing is attached: ntfy (no account: the ntfy app or ntfy.sh in a browser, `/plugin set push topic <name>`) or a Telegram bot. `/push test` checks it. |
| **proxy** | Connects the networks you pick through a SOCKS4/SOCKS5 or HTTP proxy, or an SSH jump host (`ssh -W`); the others stay direct. |
| **remind** | `/remind 10m check the build`, `/remind 1h30m ...`, `/remind 18:30 call home`: shown in that tab and the one you're on; saved, so one due while iSekur was off shows when it starts. `/remind` lists them, `/remind del 2`. |
| **seen** | `/seen nick`: when and where someone was last seen talking, joining, leaving, quitting or renaming; answers `!seen` where you turn it on. |

```
/plugin available
/plugin install seen
/plugin set seen@sekurnet reply on
/plugin update
```

All of these are official: made for iSekur by its author, Gerardo Canosa. Each one's About (in the
plugin windows) says who made a plugin and how to reach them.

Plugins are Lua 5.4, each in its own sandbox: no files, programs or sockets of their own (`isekur.http` fetches web pages for them, never from your LAN).
[WRITING.md](WRITING.md) is the guide for writing one (events, the `isekur` API, settings,
the catalog's rules). New plugins and fixes are welcome as pull requests; `python3 check.py`
must pass.

GPL-3.0-or-later, like iSekur.
